///|
fn config_base_dir(path : String) -> String {
  let raw_dirname = dirname_string(project_path_for_host(path))
  let config_dir : @mbpath.Path = raw_dirname
  config_dir.resolve().to_string()
}

///|
fn rebase_project_path(
  path : String,
  base_dir : String,
  label : String,
) -> String raise ProjectConfigError {
  validate_relative_project_path(path, label)
  let base : @mbpath.Path = project_path_for_host(base_dir)
  base.join(project_path_for_host(path)).normalize().to_string()
}

///|
/// Converts portable project separators before entering the host path API.
fn project_path_for_host(path : String) -> String {
  if @mbpath.sep == '\\' {
    path.replace_all(old="/", new="\\")
  } else {
    path
  }
}

///|
fn validate_relative_project_path(
  path : String,
  label : String,
) -> Unit raise ProjectConfigError {
  let field = if label.has_prefix("proton.project.json.") {
    label
  } else {
    "proton.project.json." + label
  }
  guard !project_path_has_root(path) else {
    raise InvalidField(
      path=field,
      expectation="must be a relative path; absolute paths and drive prefixes are not allowed",
    )
  }
  guard !path.contains("\\") else {
    raise InvalidField(
      path=field,
      expectation="must use '/' separators; backslashes are not allowed in portable project paths",
    )
  }
}

///|
fn project_path_has_root(path : String) -> Bool {
  if path.has_prefix("/") || path.has_prefix("\\") {
    return true
  }
  guard path.length() >= 2 else { return false }
  let drive = path[0]
  ((drive >= 'A' && drive <= 'Z') || (drive >= 'a' && drive <= 'z')) &&
  path[1] == ':'
}

///|
fn dirname_string(path : String) -> String {
  let native_path : @mbpath.Path = project_path_for_host(path)
  native_path.dirname().to_string()
}
