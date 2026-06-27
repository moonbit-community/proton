///|
fn has_source_cef_files(root : String) -> Bool {
  all_exist(root, source_cef_relative_files())
}

///|
fn validate_cef_root(root : String) -> Result[Unit, CliError] {
  let missing : Array[String] = []
  for relative in installed_cef_relative_files() {
    let path = path_join(root, relative)
    if !path_exists(path) {
      missing.push(path)
    }
  }
  let version_path = path_join(root, "version.txt")
  if !path_exists(version_path) {
    missing.push(version_path)
  }
  if missing.length() > 0 {
    Err(
      CliError::CommandError(
        "Invalid CEF root: " + root + "\nMissing:\n" + missing.join("\n"),
      ),
    )
  } else {
    Ok(())
  }
}

///|
fn validate_runtime_dist(root : String) -> Result[Unit, CliError] {
  let missing : Array[String] = []
  for relative in runtime_required_relative_files() {
    let path = path_join(root, relative)
    if !path_exists(path) {
      missing.push(path)
    }
  }
  if missing.length() > 0 {
    Err(
      CliError::CommandError(
        "Invalid Proton runtime: " + root + "\nMissing:\n" + missing.join("\n"),
      ),
    )
  } else {
    Ok(())
  }
}
