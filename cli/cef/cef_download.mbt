///|
async fn make_temp_dir() -> Result[String, CefError] {
  let temp_dir = @async_fs.tmpdir(prefix="proton-cef-") catch {
    err =>
      return Err(
        CefError::CommandError(
          "Failed to create temp directory: " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  if temp_dir == "" {
    Err(CefError::CommandError("Failed to create temp directory"))
  } else {
    Ok(temp_dir)
  }
}

///|
async fn download_file(
  url : String,
  destination : String,
  expected_sha256 : String,
) -> Result[Unit, CefError] {
  println("[INFO] Downloading CEF: " + url)
  let code = @process.run("curl", ["-L", "--fail", "--output", destination, url]) catch {
    err =>
      return Err(
        CefError::CommandError(
          "Download failed: " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  guard code == 0 else {
    return Err(
      CefError::CommandError(
        "Download failed: curl exited with code " + code.to_string(),
      ),
    )
  }
  verify_file_sha256(destination, expected_sha256)
}

///|
async fn verify_file_sha256(
  path : String,
  expected : String,
) -> Result[Unit, CefError] {
  let file = @async_fs.open(path, mode=ReadOnly) catch {
    err =>
      return Err(
        CefError::CommandError(
          "Failed to open downloaded CEF archive: " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  defer file.close()
  let hasher = @crypto.SHA256::new()
  let buffer = FixedArray::make(1024 * 1024, b'\x00')
  while file.read(buffer) is read && read > 0 {
    hasher.update(buffer.unsafe_reinterpret_as_bytes()[:read])
  }
  let actual = @crypto.bytes_to_hex_string(hasher.finalize())
  if actual == expected {
    Ok(())
  } else {
    Err(
      CefError::CommandError(
        "CEF archive SHA-256 mismatch: expected " + expected + ", got " + actual,
      ),
    )
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
) -> Result[String, CefError] {
  match provided {
    Some(value) => {
      let normalized = value.trim().to_owned().to_lower()
      if valid_sha256(normalized) {
        return Ok(normalized)
      }
      return Err(CefError::CommandError("Invalid CEF archive SHA-256"))
    }
    None => ()
  }
  if url is None && name == platform.default_cef_name {
    return Ok(platform.default_cef_sha256)
  }
  Err(
    CefError::CommandError("Custom CEF archive name or URL requires --sha256"),
  )
}

///|
async fn extract_tar_bz2(
  archive_path : String,
  destination : String,
) -> Result[Unit, CefError] {
  println("[INFO] Extracting: " + archive_path)
  let code = @process.run("tar", ["-xjf", archive_path, "-C", destination]) catch {
    err =>
      return Err(
        CefError::CommandError(
          "tar failed: " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  guard code == 0 else {
    return Err(
      CefError::CommandError(
        "tar failed: tar exited with code " + code.to_string(),
      ),
    )
  }
  Ok(())
}

///|
fn find_extracted_root(
  extract_dir : String,
  name : String,
  platform : ProtonPlatform,
) -> Result[String, CefError] {
  let named = path_join(extract_dir, name)
  if has_source_cef_files(named, platform) {
    return Ok(named)
  }
  let candidates : Array[String] = []
  let entries = @mbfs.read_dir(extract_dir) catch {
    err =>
      return Err(
        CefError::CommandError(
          "Failed to read extract directory: " +
          @debug.render(@debug.to_repr(err)),
        ),
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
    [candidate] => Ok(candidate)
    _ =>
      Err(
        CefError::CommandError(
          "Could not find extracted CEF root in " + extract_dir,
        ),
      )
  }
}
