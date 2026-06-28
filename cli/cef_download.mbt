///|
async fn make_temp_dir() -> Result[String, CliError] {
  let temp_dir = @async_fs.tmpdir(prefix="proton-cef-") catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to create temp directory: " +
          @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  if temp_dir == "" {
    Err(CliError::CommandError("Failed to create temp directory"))
  } else {
    Ok(temp_dir)
  }
}

///|
async fn download_file(
  url : String,
  destination : String,
) -> Result[Unit, CliError] {
  println("[INFO] Downloading CEF: " + url)
  let code = @process.run("curl", ["-L", "--fail", "--output", destination, url]) catch {
    err =>
      return Err(
        CliError::CommandError(
          "Download failed: " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  guard code == 0 else {
    return Err(
      CliError::CommandError(
        "Download failed: curl exited with code " + code.to_string(),
      ),
    )
  }
  Ok(())
}

///|
async fn extract_tar_bz2(
  archive_path : String,
  destination : String,
) -> Result[Unit, CliError] {
  println("[INFO] Extracting: " + archive_path)
  let code = @process.run("tar", ["-xjf", archive_path, "-C", destination]) catch {
    err =>
      return Err(
        CliError::CommandError(
          "tar failed: " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  guard code == 0 else {
    return Err(
      CliError::CommandError(
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
) -> Result[String, CliError] {
  let named = path_join(extract_dir, name)
  if has_source_cef_files(named, platform) {
    return Ok(named)
  }
  let candidates : Array[String] = []
  let entries = @mbfs.read_dir(extract_dir) catch {
    err =>
      return Err(
        CliError::CommandError(
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
        CliError::CommandError(
          "Could not find extracted CEF root in " + extract_dir,
        ),
      )
  }
}
