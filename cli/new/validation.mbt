///|
let default_project_path = "counter"

///|
let default_width = 960

///|
let default_height = 640

///|
fn new_path_join(base : String, child : String) -> String {
  if base == "" {
    child
  } else if child == "" {
    base
  } else if base.has_suffix("\\") || base.has_suffix("/") {
    base + child
  } else {
    base + @path.sep.to_string() + child
  }
}

///|
fn new_path_is_absolute(path : String) -> Bool {
  @path.Path(path).is_absolute()
}

///|
fn resolve_new_path(cwd : String, target : String) -> String {
  let raw = if new_path_is_absolute(target) {
    target
  } else {
    new_path_join(cwd, target)
  }
  @path.Path(raw).resolve().to_string()
}

///|
fn path_exists(path : String) -> Bool {
  @mbfs.path_exists(path)
}

///|
fn path_is_dir(path : String) -> Bool {
  @mbfs.is_dir(path) catch {
    _ => false
  }
}

///|
fn path_basename(path : String) -> String {
  let normalized = normalize_slashes(path)
  let trimmed = trim_trailing_slashes(normalized)
  if trimmed == "" {
    default_project_path
  } else {
    let slash = trimmed.rev_find("/")
    match slash {
      Some(index) =>
        trimmed.unsafe_substring(start=index + 1, end=trimmed.length())
      None => trimmed
    }
  }
}

///|
fn project_slug(cwd : String, target : String) -> String {
  match path_basename(target) {
    "." => path_basename(cwd)
    ".." => path_basename(new_path_parent(cwd))
    slug => slug
  }
}

///|
fn normalize_slashes(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
fn trim_trailing_slashes(path : String) -> String {
  let mut end = path.length()
  while end > 0 && (path[end - 1] == '/' || path[end - 1] == '\\') {
    end = end - 1
  }
  path.unsafe_substring(start=0, end~)
}

///|
fn slug_to_title(slug : String) -> String {
  @case.title_case(slug)
}

///|
fn default_bundle_identifier(slug : String) -> String {
  let component = slug
    .replace_all(old="_", new="-")
    .replace_all(old=".", new="-")
  let component = if component == "" {
    "app"
  } else if starts_with_ascii_alphanumeric(component) {
    component
  } else {
    "app-" + component
  }
  "dev.proton." + component
}

///|
fn starts_with_ascii_alphanumeric(value : String) -> Bool {
  for char in value {
    return char.is_ascii_alphabetic() || char.is_ascii_digit()
  }
  false
}

///|
fn validate_bundle_identifier(identifier : String) -> Result[Unit, String] {
  let value = identifier.trim().to_owned()
  let components : Array[StringView] = value.split(".").collect()
  guard components.length() >= 2 else {
    return Err("identifier must be a reverse-DNS bundle identifier: " + value)
  }
  for component in components {
    guard component.length() > 0 else {
      return Err("identifier contains an empty component: " + value)
    }
    let mut at_start = true
    for char in component {
      if at_start {
        guard char.is_ascii_alphabetic() || char.is_ascii_digit() else {
          return Err(
            "identifier component must start with an ASCII letter or digit: " +
            value,
          )
        }
        at_start = false
      }
      guard char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '-' else {
        return Err("identifier contains an unsupported character: " + value)
      }
    }
  }
  Ok(())
}

///|
fn parse_positive_int(value : String, label : String) -> Result[Int, String] {
  let parsed = @string.parse_int(value[:]) catch {
    _ => return Err(label + " must be a positive integer: " + value)
  }
  if parsed <= 0 {
    Err(label + " must be a positive integer: " + value)
  } else {
    Ok(parsed)
  }
}

///|
fn validate_module_name(module_name : String) -> Result[Unit, String] {
  if module_name.trim().is_empty() {
    return Err("module name must not be empty")
  }
  if module_name.contains("\\") {
    return Err("module name must use '/' instead of '\\'")
  }
  if module_name.has_prefix("/") || module_name.has_suffix("/") {
    return Err("module name must not start or end with '/'")
  }
  if module_name.contains(" ") {
    return Err("module name must not contain spaces")
  }
  if module_name.contains("//") {
    return Err("module name must not contain empty path segments")
  }
  for ch in module_name {
    if !module_name_char_is_valid(ch) {
      return Err(
        "module name contains unsupported character: " + ch.to_string(),
      )
    }
  }
  Ok(())
}

///|
fn module_name_char_is_valid(ch : Char) -> Bool {
  ch.is_ascii_alphabetic() ||
  ch.is_ascii_digit() ||
  ch == '/' ||
  ch == '_' ||
  ch == '-' ||
  ch == '.'
}

///|
fn validate_title(title : String) -> Result[Unit, String] {
  if title.trim().is_empty() {
    Err("app title must not be empty")
  } else {
    Ok(())
  }
}

///|
fn validate_target_dir(target_dir : String) -> Result[Unit, String] {
  if target_dir.trim().is_empty() {
    Err("project directory must not be empty")
  } else {
    Ok(())
  }
}

///|
fn target_dir_is_empty(target_dir : String) -> Result[Bool, String] {
  if !path_exists(target_dir) {
    return Ok(true)
  }
  if !path_is_dir(target_dir) {
    return Err("target path is not a directory: " + target_dir)
  }
  let entries = @mbfs.read_dir(target_dir) catch {
    err =>
      return Err(
        "failed to read target directory: " + @debug.render(@debug.to_repr(err)),
      )
  }
  Ok(entries.length() == 0)
}

///|
fn validate_target_dir_for_write(target_dir : String) -> Result[Unit, String] {
  let moon_mod_path = new_path_join(target_dir, "moon.mod")
  if path_exists(moon_mod_path) {
    return Err("target directory already contains moon.mod: " + target_dir)
  }
  match target_dir_is_empty(target_dir) {
    Err(message) => Err(message)
    Ok(true) => Ok(())
    Ok(false) =>
      Err(
        "target directory is not empty: " +
        target_dir +
        "\n\nChoose a different directory:\n  proton_cli new " +
        path_basename(target_dir) +
        "-2\n\nOr remove files manually and retry.",
      )
  }
}
