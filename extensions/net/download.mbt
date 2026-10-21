///|
/// Progress of a host-side download. Counts bytes written to the temporary file.
/// `total_bytes` is absent when the decoded response size is unknown.
pub(all) struct DownloadProgress {
  received_bytes : Int64
  total_bytes : Int64?
} derive(Debug, Eq)

///|
pub extend DownloadProgress with Debug::{to_repr}

///|
pub extend DownloadProgress with Eq::{equal, not_equal}

///|
/// Failures of a host-side download. Cancellation retains its async semantics.
/// A cleanup failure preserves the primary error, if any, and the temporary
/// path so that a file which could not be removed can be located.
pub(all) suberror DownloadError {
  InvalidRequest(detail~ : String)
  HttpStatus(status~ : Int32)
  DestinationExists(path~ : String)
  NetworkFailed(detail~ : String)
  FileFailed(detail~ : String)
  CleanupFailed(primary~ : DownloadError?, path~ : String, detail~ : String)
} derive(Debug)

///|
pub extend DownloadError with Debug::{to_repr}

///|
let download_random : @random.Rand = @random.Rand::chacha8()

///|
async fn create_download_file(destination : String) -> (String, @fs.File) {
  let directory = @path.Path(destination).dirname()
  for nonce = download_random.uint64() {
    let name = ".proton-download-\{nonce.to_string(radix=16)}.part"
    let temporary = directory.join(@path.Path(name)).to_string()
    try {
      let file = @fs.create(temporary, allow_existing=false, permission=0o600)
      return (temporary, file)
    } catch {
      @os_error.OSError(_) as error if error.is_EEXIST() =>
        continue download_random.uint64()
      error => raise error
    }
  }
}

///|
/// Downloads a complete HTTP(S) GET response to `destination` on the host.
/// Headers belong only to this request. Only HTTP 200 is accepted; redirects
/// and partial responses are not followed or saved. Browser cookies, download
/// handlers and events are not used, and no renderer command is registered.
/// Temporarily requests identity encoding by default and rejects encoded
/// responses until async/http fixes close-delimited gzip decoding.
///
/// The parent directory must exist. Bytes are streamed to an exclusive sibling
/// temporary file, then moved to the destination. Existing files are preserved
/// unless `overwrite=true`; failure before the move preserves the old file.
/// Cancellation closes the connection and removes the temporary file. Once the
/// final move starts it completes without cancellation; a committed destination
/// is never removed by cancellation cleanup. This is not a crash-recovery API.
///
/// The optional synchronous observer receives coalesced progress, including the
/// final byte count before file submission. Only successful return confirms the
/// destination was saved. Timeouts can be imposed with `@async.with_timeout`.
pub async fn download(
  url : String,
  destination : String,
  headers~ : Map[String, String] = {},
  overwrite~ : Bool = false,
  on_progress? : (DownloadProgress) -> Unit noraise,
) -> Unit raise DownloadError {
  let (origin, target) = split_url(url) catch {
    _ => raise InvalidRequest(detail="expected an absolute HTTP(S) URL")
  }
  guard !destination.is_empty() else {
    raise InvalidRequest(detail="destination must be a file path")
  }
  // FIXME: https://github.com/moonbitlang/x/issues/351 tracks anchoring paths
  // without changing filesystem traversal. resolve() lexically collapses
  // symlink/.. and can select the wrong destination (overwriting another file).
  // Preserve parent traversal and the final entry's replacement semantics;
  // account for create_download_file's normalizing join and Windows paths too.
  let destination = @path.Path(destination).resolve().to_string()
  let headers = request_headers(headers)
  guard !headers.contains("Range") else {
    raise InvalidRequest(detail="partial downloads are not supported")
  }
  // FIXME: Remove this workaround after upgrading to async with the fix for
  // https://github.com/moonbitlang/async/issues/672. Close-delimited gzip can
  // bypass decoding. Request identity and reject encoded responses rather than
  // silently saving compressed bytes, even if the server ignores negotiation.
  if !headers.contains("Accept-Encoding") {
    headers["Accept-Encoding"] = "identity"
  }
  let (response, client) = @http.get_stream(
    origin + target[1:].to_owned(),
    headers~,
  ) catch {
    error => raise NetworkFailed(detail=@debug.render(Repr(error)))
  }
  defer client.close()
  guard response.code == 200 else { raise HttpStatus(status=response.code) }
  if response.headers.get("Content-Encoding") is Some(encoding) &&
    encoding.trim().to_owned().to_lower() != "identity" {
    raise NetworkFailed(
      detail="encoded download responses are temporarily unsupported; expected identity encoding",
    )
  }
  let total_bytes = if response.headers.contains("Transfer-Encoding") {
    None
  } else {
    match response.headers.get("Content-Length") {
      Some(value) =>
        try @string.parse_int64(value[:]) catch {
          _ => None
        } noraise {
          size => if size >= 0 { Some(size) } else { None }
        }
      None => None
    }
  }
  // Protect acquisition until ownership is recorded, not the network transfer.
  let (temporary, file) = @async.protect_from_cancel(() => {
    create_download_file(destination)
  }) catch {
    error => raise FileFailed(detail=@debug.render(Repr(error)))
  }
  let mut committed = false
  let mut primary = None
  defer {
    file.close()
    if !committed {
      @fs.remove(temporary) catch {
        error =>
          raise CleanupFailed(
            primary~,
            path=temporary,
            detail=@debug.render(Repr(error)),
          )
      }
    }
  }
  try {
    let mut received = 0L
    let mut last_notice = @async.now()
    let mut notified = -1L
    if on_progress is Some(notify) {
      notify({ received_bytes: received, total_bytes, })
      notified = received
    }
    while (client.read_some(max_len=65536) catch {
            error => raise NetworkFailed(detail=@debug.render(Repr(error)))
          })
          is Some(chunk) {
      file.write(chunk) catch {
        error => raise FileFailed(detail=@debug.render(Repr(error)))
      }
      received += chunk.length().to_int64()
      let now = @async.now()
      if now - last_notice >= 100 && on_progress is Some(notify) {
        notify({ received_bytes: received, total_bytes, })
        last_notice = now
        notified = received
      }
    }
    if notified != received && on_progress is Some(notify) {
      notify({ received_bytes: received, total_bytes, })
    }
    file.sync(only_data=true) catch {
      error => raise FileFailed(detail=@debug.render(Repr(error)))
    }
    file.close()
    // Observe pending cancellation before entering the short commit section.
    @async.pause()
    @async.protect_from_cancel(() => {
      @fs.rename(temporary, destination, replace=overwrite)
      committed = true
    }) catch {
      @os_error.OSError(_) as error if error.is_EEXIST() =>
        raise DestinationExists(path=destination)
      error => raise FileFailed(detail=@debug.render(Repr(error)))
    }
  } catch {
    error => primary = Some(error)
  }
  if primary is Some(error) {
    raise error
  }
}
