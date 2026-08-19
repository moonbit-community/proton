///|
let request_command = @net_contract.request

///|
/// Parses a method string into the `@http.RequestMethod` enum.
fn parse_method(meth : String) -> @http.RequestMethod raise NetError {
  match meth.to_upper() {
    "GET" => @http.Get
    "POST" => @http.Post
    "PUT" => @http.Put
    "DELETE" => @http.Delete
    "PATCH" => @http.Patch
    "HEAD" => @http.Head
    "OPTIONS" => @http.Options
    _ => raise UnsupportedMethod(name=meth)
  }
}

///|
/// Splits a URL into `(base_url, path)` where `base_url` has a trailing slash
/// and is suitable for `@http.Client::Client`.
fn split_url(url : String) -> (String, String) raise NetError {
  let (prefix, rest) = if url.has_prefix("https://") {
    ("https://", url[8:].to_owned())
  } else if url.has_prefix("http://") {
    ("http://", url[7:].to_owned())
  } else {
    raise InvalidUrl(detail="URL must start with http:// or https://")
  }
  match rest.find("/") {
    Some(slash) => {
      let host = rest[:slash].to_owned()
      let path = rest[slash:].to_owned()
      (prefix + host + "/", path)
    }
    None => (url + "/", "/")
  }
}

///|
/// Makes an HTTP request and returns the response.
#proton.command(contract=request_command)
async fn do_request(
  _context : @proton.CommandContext,
  request : @net_contract.Request,
) -> @net_contract.Response {
  let meth = parse_method(request.http_method)
  let headers = request.headers
  let body_bytes = request.body.map(fn(s) { @utf8.encode(s) }).unwrap_or(b"")
  // Use top-level functions for GET/POST/PUT (they handle full URL parsing).
  // Use Client for DELETE, PATCH, HEAD, OPTIONS (need URL split + path).
  let (response, data) = match meth {
    Get =>
      @http.get(request.url, headers~) catch {
        error => raise RequestFailed(detail=@debug.render(Repr(error)))
      }
    Post =>
      @http.post(request.url, body_bytes, headers~) catch {
        error => raise RequestFailed(detail=@debug.render(Repr(error)))
      }
    Put =>
      @http.put(request.url, body_bytes, headers~) catch {
        error => raise RequestFailed(detail=@debug.render(Repr(error)))
      }
    _ => {
      let (base_url, path) = split_url(request.url)
      let client = @http.Client::Client(base_url, headers~) catch {
        error => raise RequestFailed(detail=@debug.render(Repr(error)))
      }
      defer client.close()
      let response = client
        ..request(meth, path)
        ..write(body_bytes)
        .end_request() catch {
          error => raise RequestFailed(detail=@debug.render(Repr(error)))
        }
      let data = client.read_all()
      (response, data)
    }
  }
  @net_contract.Response::{
    status: response.code,
    status_text: response.reason,
    headers: response.headers,
    body: @utf8.decode_lossy(data.binary()),
  }
}

///|
pub fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @net_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
  )
}
