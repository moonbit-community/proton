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
async fn download_file(
  url : String,
  destination : String,
  expected_sha256 : String,
) -> Unit {
  report_info("[INFO] Downloading CEF: " + url)
  let code = @process.run("curl", [
    "-L", "--fail", "--retry", "5", "--retry-all-errors", "--retry-delay", "2", "--connect-timeout",
    "30", "--output", destination, url,
  ]) catch {
    err => raise CefDownloadError::Start(url~, detail=@debug.render(Repr(err)))
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
async fn extract_tar_bz2(archive_path : String, destination : String) -> Unit {
  report_info("[INFO] Extracting: " + archive_path)
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
  let named = path_join(extract_dir, name)
  if has_source_cef_files(named, platform) {
    return named
  }
  raise CefDownloadError::ExtractedRootNotFound(path=named)
}
