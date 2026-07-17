///|
fn config_base_dir(path : String) -> String {
  let raw_dirname = dirname_string(path)
  let config_dir : @mbpath.Path = raw_dirname
  config_dir.resolve().to_string()
}

///|
fn rebase_project_path(path : String, base_dir : String) -> String {
  let candidate : @mbpath.Path = path
  if candidate.is_absolute() {
    path
  } else {
    let base : @mbpath.Path = base_dir
    base.join(path).normalize().to_string()
  }
}

///|
fn join_path_string(base : String, child : String) -> String {
  let base_path : @mbpath.Path = base
  base_path.join(child).normalize().to_string()
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
