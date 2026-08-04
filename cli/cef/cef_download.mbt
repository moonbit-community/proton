///|
async fn make_temp_dir() -> String {
  let temp_dir = @async_fs.tmpdir(prefix="proton-cef-") catch {
    err =>
      raise CefDownloadError::CreateTemporaryDirectory(
        detail=@debug.render(Repr(err)),
      )
  }
  if temp_dir == "" {
    raise CefDownloadError::CreateTemporaryDirectory(detail="empty path")
  } else {
    temp_dir
  }
}

///|
let cef_download_max_attempts = 3

///|
let cef_download_retry_delay_ms = 2000

///|
async fn download_file(
  url : String,
  destination : String,
  expected_sha256 : String,
) -> Unit {
  @output.info("[INFO] Downloading CEF: " + url)
  let mut last_code = 1
  for attempt in 1..<=cef_download_max_attempts {
    let code = @process.run("curl", [
      "-L", "--fail", "--retry", "5", "--retry-all-errors", "--retry-delay", "2",
      "--connect-timeout", "30", "--output", destination, url,
    ]) catch {
      err =>
        raise CefDownloadError::Start(url~, detail=@debug.render(Repr(err)))
    }
    if code == 0 {
      verify_file_sha256(destination, expected_sha256)
      return
    }
    last_code = code
    if attempt < cef_download_max_attempts {
      @output.info(
        "[INFO] CEF download attempt " +
        attempt.to_string() +
        " failed (curl exit " +
        code.to_string() +
        "); retrying",
      )
      @async.sleep(cef_download_retry_delay_ms)
    }
  }
  raise CefDownloadError::CurlExit(url~, code=last_code)
}

///|
async fn verify_file_sha256(path : String, expected : String) -> Unit {
  let file = @async_fs.open(path, mode=ReadOnly) catch {
    err =>
      raise CefDownloadError::OpenArchive(
        path~,
        detail=@debug.render(Repr(err)),
      )
  }
  defer file.close()
  let hasher = @crypto.SHA256::new()
  let buffer = FixedArray::make(1024 * 1024, b'\x00')
  while file.read(buffer) is read && read > 0 {
    hasher.update(buffer.unsafe_reinterpret_as_bytes()[:read])
  }
  let actual = @crypto.bytes_to_hex_string(hasher.finalize())
  if actual != expected {
    raise CefDownloadError::ChecksumMismatch(expected~, actual~)
  }
}

///|
fn valid_sha256(value : String) -> Bool {
  if value.length() != 64 {
    return false
  }
  for ch in value {
    guard ch.is_ascii_digit() || (ch >= 'a' && ch <= 'f') else { return false }
  }
  true
}

///|
fn resolve_cef_archive_sha256(
  platform : ProtonPlatform,
  name : String,
  url : String?,
  provided : String?,
) -> String raise CefUsageError {
  match provided {
    Some(value) => {
      let normalized = value.trim().to_owned().to_lower()
      if valid_sha256(normalized) {
        return normalized
      }
      raise InvalidChecksum(value~)
    }
    None => ()
  }
  if url is None && name == platform.default_cef_name {
    return platform.default_cef_sha256
  }
  raise MissingCustomChecksum
}

///|
async fn extract_tar_bz2(archive_path : String, destination : String) -> Unit {
  @output.info("[INFO] Extracting: " + archive_path)
  let code = @process.run("tar", ["-xjf", archive_path, "-C", destination]) catch {
    err =>
      raise CefDownloadError::ExtractStart(
        path=archive_path,
        detail=@debug.render(Repr(err)),
      )
  }
  guard code == 0 else {
    raise CefDownloadError::ExtractExit(path=archive_path, code~)
  }
}

///|
async fn find_extracted_root(
  extract_dir : String,
  name : String,
  platform : ProtonPlatform,
) -> String {
  let named = @fsutil.path_join(extract_dir, name)
  if has_source_cef_files(named, platform) {
    return named
  }
  let candidates : Array[String] = []
  let entries = @async_fs.readdir(
    extract_dir,
    include_hidden=true,
    include_special=false,
  ) catch {
    err =>
      raise CefFileSystemError::ReadDirectory(
        path=extract_dir,
        detail=@debug.render(Repr(err)),
      )
  }
  for entry in entries {
    guard entry.has_prefix("cef_binary_") else { continue }
    let candidate = @fsutil.path_join(extract_dir, entry)
    if @fsutil.path_is_dir(candidate) &&
      has_source_cef_files(candidate, platform) {
      candidates.push(candidate)
    }
  }
  match candidates {
    [candidate] => candidate
    _ => raise CefDownloadError::ExtractedRootNotFound(path=extract_dir)
  }
}
