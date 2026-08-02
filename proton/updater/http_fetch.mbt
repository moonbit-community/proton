///|
/// The largest body this client will accept from an update endpoint.
///
/// A manifest and a signature are both small. A server that offers something
/// enormous in their place is either broken or hostile, and either way the
/// client should stop rather than fill memory on the way to a signature check
/// it was going to fail.
pub let maximum_metadata_bytes : Int = 1024 * 1024

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
  let (response, body) = @http.get(url) catch {
    error => raise FetchFailed(url~, detail=@debug.render(Repr(error)))
  }
  guard response.code == 200 else {
    raise FetchFailed(url~, detail="server responded \{response.code}")
  }
  let bytes = body.binary()
  guard bytes.length() <= maximum_metadata_bytes else {
    raise FetchFailed(
      url~,
      detail="body is \{bytes.length()} bytes, over the \{maximum_metadata_bytes} byte limit",
    )
  }
  bytes
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
  let (response, client) = @http.get_stream(url) catch {
    error => raise FetchFailed(url~, detail=@debug.render(Repr(error)))
  }
  defer client.close()
  guard response.code == 200 else {
    raise FetchFailed(url~, detail="server responded \{response.code}")
  }
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
