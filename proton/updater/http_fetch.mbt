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
    let next = @uri.UriRef::parse(location).resolve_against(
      @uri.Uri::parse(current),
    ) catch {
      _ =>
        raise FetchFailed(
          url=current,
          detail="invalid redirect Location: \{location}",
        )
    }
    let scheme = next.scheme.as_str()
    guard scheme.to_lower() == "https" else {
      raise FetchFailed(url=current, detail="redirect target must use https")
    }
    // The HTTP transport expects a lowercase scheme; preserve the signed
    // path and query text while omitting the fragment from the request.
    let text = next.strip_fragment().text
    continue "https" + text[scheme.length():].to_owned(), redirects + 1
  }
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
