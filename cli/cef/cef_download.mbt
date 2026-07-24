///|
async fn make_temp_dir() -> String {
  let temp_dir = @async_fs.tmpdir(prefix="proton-cef-") catch {
    err =>
      raise CefDownloadError::CreateTemporaryDirectory(
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
  if temp_dir == "" {
    raise CefDownloadError::CreateTemporaryDirectory(detail="empty path")
  } else {
    temp_dir
  }
}

///|
async fn download_file(
  url : String,
  destination : String,
  expected_sha256 : String,
) -> Unit {
  println("[INFO] Downloading CEF: " + url)
  let code = @process.run("curl", ["-L", "--fail", "--output", destination, url]) catch {
    err =>
      raise CefDownloadError::Start(
        url~,
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
  guard code == 0 else { raise CefDownloadError::CurlExit(url~, code~) }
  verify_file_sha256(destination, expected_sha256)
}

///|
async fn verify_file_sha256(path : String, expected : String) -> Unit {
  let file = @async_fs.open(path, mode=ReadOnly) catch {
    err =>
      raise CefDownloadError::OpenArchive(
        path~,
        detail=@debug.render(@debug.to_repr(err)),
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
  println("[INFO] Extracting: " + archive_path)
  let code = @process.run("tar", ["-xjf", archive_path, "-C", destination]) catch {
    err =>
      raise CefDownloadError::ExtractStart(
        path=archive_path,
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
  guard code == 0 else {
    raise CefDownloadError::ExtractExit(path=archive_path, code~)
  }
}

///|
fn find_extracted_root(
  extract_dir : String,
  name : String,
  platform : ProtonPlatform,
) -> String raise {
  let named = path_join(extract_dir, name)
  if has_source_cef_files(named, platform) {
    return named
  }
  let candidates : Array[String] = []
  let entries = @mbfs.read_dir(extract_dir) catch {
    err =>
      raise CefFileSystemError::ReadDirectory(
        path=extract_dir,
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
  for entry in entries {
    guard entry.has_prefix("cef_binary_") else { continue }
    let candidate = path_join(extract_dir, entry)
    if path_is_dir(candidate) && has_source_cef_files(candidate, platform) {
      candidates.push(candidate)
    }
  }
  match candidates {
    [candidate] => candidate
    _ => raise CefDownloadError::ExtractedRootNotFound(path=extract_dir)
  }
}
