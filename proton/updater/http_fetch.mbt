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
/// Fetches an artifact over HTTPS.
///
/// Separate from `http_fetch` because an artifact is not metadata: it is
/// expected to be large, so the small-body limit does not apply. Its length is
/// checked against the signed manifest rather than against a constant, which is
/// a stronger bound than any figure that could be written here.
pub async fn http_fetch_artifact(url : String) -> Bytes raise UpdateError {
  guard url.has_prefix("https://") else {
    raise FetchFailed(url~, detail="only https URLs are fetched")
  }
  let (response, body) = @http.get(url) catch {
    error => raise FetchFailed(url~, detail=@debug.render(Repr(error)))
  }
  guard response.code == 200 else {
    raise FetchFailed(url~, detail="server responded \{response.code}")
  }
  body.binary()
}

///|
/// Returns an artifact fetch that reports how many bytes have arrived.
///
/// The progress callback is baked into the fetch rather than added to
/// `UpdateChannel::download`, because whether progress can be reported at all
/// is a property of how the bytes are obtained. A caller that supplies its own
/// transport is not obliged to invent one.
///
/// A failing progress callback does not fail the download.
///
/// Nothing about the result is trusted any more than the non-streaming fetch:
/// the whole body is still checked against the signed size, digest and
/// signature before anything is done with it. Progress is a number for a
/// progress bar, not a reason to act on a prefix.
pub fn http_fetch_artifact_reporting(
  on_progress : async (Int64) -> Unit,
) -> Fetch {
  async fn(url : String) -> Bytes raise UpdateError {
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
    let chunks : Array[Bytes] = []
    let mut received = 0L
    while (client.read_some() catch {
            error => raise FetchFailed(url~, detail=@debug.render(Repr(error)))
          })
          is Some(chunk) {
      received = received + chunk.length().to_int64()
      chunks.push(chunk)
      // A progress report that fails is dropped. It exists to move a progress
      // bar; letting it end a transfer would make the cosmetic part of this
      // able to break the part that matters.
      on_progress(received) catch {
        _ => ()
      }
    }
    let body : Array[Byte] = []
    for chunk in chunks {
      for byte in chunk {
        body.push(byte)
      }
    }
    Bytes::from_array(body)
  }
}
