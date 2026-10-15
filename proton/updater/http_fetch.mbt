///|
/// The largest body this client will accept from an update endpoint.
///
/// A manifest and a signature are both small. A server that offers something
/// enormous in their place is either broken or hostile, and either way the
/// client should stop rather than fill memory on the way to a signature check
/// it was going to fail.
pub let maximum_metadata_bytes : Int32 = 1024 * 1024

///|
/// Opens the final response, closing each redirect before the next request.
/// Public fetch entry points require HTTPS before calling this helper.
async fn open_update_stream(
  url : String,
) -> (@http.Response, @http.Client) raise UpdateError {
  for current = url, redirects = 0 {
    let (response, client) = @http.get_stream(current) catch {
      error => raise FetchFailed(url=current, detail=@debug.render(Repr(error)))
    }
    if response.code == 200 {
      return (response, client)
    }
    client.close()
    guard response.code is (301 | 302 | 303 | 307 | 308) else {
      raise FetchFailed(url=current, detail="server responded \{response.code}")
    }
    guard redirects < 5 else {
      raise FetchFailed(
        url=current,
        detail="update redirect limit (5) exceeded",
      )
    }
    guard response.headers.get("location") is Some(location) else {
      raise FetchFailed(
        url=current,
        detail="redirect response has no Location header",
      )
    }
    continue update_redirect_url(current, location), redirects + 1
  }
}

///|
/// Resolve URI components without decoding or normalizing signed paths.
fn update_redirect_url(
  base_url : String,
  location : String,
) -> String raise UpdateError {
  let (base, target) = (@uri.Uri::parse(base_url), @uri.UriRef::parse(location)) catch {
    _ =>
      raise FetchFailed(
        url=base_url,
        detail="invalid redirect Location: \{location}",
      )
  }
  let scheme = target.scheme
    .map(s => s.as_str())
    .unwrap_or(base.scheme.as_str())
  guard scheme.to_lower() == "https" else {
    raise FetchFailed(url=base_url, detail="redirect target must use https")
  }
  let (authority, path, query) = if target.scheme is Some(_) ||
    target.authority is Some(_) {
    (target.authority, target.path.as_str(), target.query)
  } else if target.path.as_str().is_empty() {
    (
      base.authority,
      base.path.as_str(),
      match target.query {
        Some(_) => target.query
        None => base.query
      },
    )
  } else {
    let path = target.path.as_str()
    let merged = if path.has_prefix("/") {
      path
    } else {
      let base_path = base.path.as_str()
      match base_path.rev_find("/") {
        Some(index) => base_path[:index + 1].to_owned() + path
        None => "/" + path
      }
    }
    // RFC 3986 dot segments are literal '.' and '..'; %2E is path data.
    let segments : Array[String] = []
    let parts = merged.split("/").collect()
    for i, part in parts {
      match part {
        "." => ()
        ".." => if segments.length() > 1 { ignore(segments.pop()) }
        _ => segments.push(part.to_owned())
      }
      if i == parts.length() - 1 && (part == "." || part == "..") {
        segments.push("")
      }
    }
    (base.authority, segments.join("/"), target.query)
  }
  guard authority is Some(authority) && !authority.host.is_empty() else {
    raise FetchFailed(url=base_url, detail="redirect target must have a host")
  }
  // async/http splits authority from the request target at the first '/'.
  let path = if path.is_empty() { "/" } else { path }
  let query = match query {
    Some(query) => "?" + query.as_str()
    None => ""
  }
  "https://" + authority.as_str() + path + query
}

///|
/// Fetches update metadata over HTTPS.
///
/// Plain HTTP is refused. The signature is what makes a response trustworthy,
/// so TLS is not what protects this exchange — but there is no reason to
/// advertise which release a user is running to anyone on the path, and no
/// reason to accept a redirect into cleartext.
pub async fn http_fetch(url : String) -> Bytes raise UpdateError {
  guard url.has_prefix("https://") else {
    raise FetchFailed(url~, detail="only https URLs are fetched")
  }
  fetch_metadata_stream(url)
}

///|
async fn fetch_metadata_stream(url : String) -> Bytes raise UpdateError {
  let (_, client) = open_update_stream(url)
  defer client.close()
  let buffer = @buffer.Buffer()
  while (client.read_some(max_len=8192) catch {
          error => raise FetchFailed(url~, detail=@debug.render(Repr(error)))
        })
        is Some(chunk) {
    guard chunk.length() <= maximum_metadata_bytes - buffer.length() else {
      raise FetchFailed(
        url~,
        detail="body exceeds the \{maximum_metadata_bytes} byte limit",
      )
    }
    buffer.write_bytes(chunk)
  }
  buffer.to_bytes()
}

///|
/// Streams an artifact over HTTPS without retaining its body.
///
/// `expected_size` comes from the authenticated manifest. A `Content-Length`
/// mismatch can therefore be refused before reading the body, but the consumer
/// still counts actual chunks because the header may be absent after content
/// decoding or on a chunked response.
pub async fn http_fetch_artifact(
  url : String,
  expected_size : Int64,
  consume : async (Bytes) -> Unit raise UpdateError,
) -> Unit raise UpdateError {
  guard url.has_prefix("https://") else {
    raise FetchFailed(url~, detail="only https URLs are fetched")
  }
  let (response, client) = open_update_stream(url)
  defer client.close()
  match response.headers.get("content-length") {
    Some(text) => {
      let declared = @string.parse_int64(text[:]) catch {
        error => raise FetchFailed(url~, detail=@debug.render(Repr(error)))
      }
      guard declared == expected_size else {
        raise ArtifactSizeMismatch(expected=expected_size, actual=declared)
      }
    }
    None => ()
  }
  let mut received = 0L
  while (client.read_some() catch {
          error => raise FetchFailed(url~, detail=@debug.render(Repr(error)))
        })
        is Some(chunk) {
    let chunk_size = chunk.length().to_int64()
    let actual_size = artifact_size_after_chunk(
      expected_size, received, chunk_size,
    )
    consume(chunk)
    received = actual_size
    if received == expected_size {
      return
    }
  }
  guard received == expected_size else {
    raise ArtifactSizeMismatch(expected=expected_size, actual=received)
  }
}
