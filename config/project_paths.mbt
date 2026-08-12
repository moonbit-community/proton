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
fn join_path_string(base : String, child : String) -> String {
  let base_path : @mbpath.Path = project_path_for_host(base)
  base_path.join(project_path_for_host(child)).normalize().to_string()
}

///|
fn dirname_string(path : String) -> String {
  let mut separator_index : Int? = None
  for i, ch in path {
    if ch == '/' || ch == '\\' {
      separator_index = Some(i)
    }
  }
  match separator_index {
    None => "."
    Some(separator_index) => prefix_string(path, separator_index)
  }
}

///|
fn prefix_string(path : String, end_exclusive : Int) -> String {
  let builder = StringBuilder::new(size_hint=end_exclusive)
  for i, ch in path {
    if i >= end_exclusive {
      break
    }
    builder.write_char(ch)
  }
  builder.to_string()
}

///|
fn normalize_keyword(raw : String) -> String {
  raw.trim().to_owned().to_lower()
}
