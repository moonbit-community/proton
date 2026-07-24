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
fn validate_bundle_identifier(
  identifier : String,
) -> Unit raise NewProjectInputError {
  let value = identifier.trim().to_owned()
  let components : Array[StringView] = value.split(".").collect()
  guard components.length() >= 2 else {
    raise InvalidBundleIdentifier(
      identifier=value,
      reason="expected a reverse-DNS name",
    )
  }
  for component in components {
    guard component.length() > 0 else {
      raise InvalidBundleIdentifier(
        identifier=value,
        reason="contains an empty component",
      )
    }
    let mut at_start = true
    for char in component {
      if at_start {
        guard char.is_ascii_alphabetic() || char.is_ascii_digit() else {
          raise InvalidBundleIdentifier(
            identifier=value,
            reason="a component must start with an ASCII letter or digit",
          )
        }
        at_start = false
      }
      guard char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '-' else {
        raise InvalidBundleIdentifier(
          identifier=value,
          reason="contains an unsupported character",
        )
      }
    }
  }
}

///|
fn parse_positive_int(
  value : String,
  label : String,
) -> Int raise NewProjectInputError {
  let parsed = @string.parse_int(value[:]) catch {
    _ => raise InvalidPositiveInteger(field=label, value~)
  }
  if parsed <= 0 {
    raise InvalidPositiveInteger(field=label, value~)
  } else {
    parsed
  }
}

///|
fn validate_module_name(
  module_name : String,
) -> Unit raise NewProjectInputError {
  if module_name.trim().is_empty() {
    raise EmptyModuleName
  }
  if module_name.contains("\\") {
    raise ModuleUsesBackslash
  }
  if module_name.has_prefix("/") || module_name.has_suffix("/") {
    raise ModuleHasBoundarySlash
  }
  if module_name.contains(" ") {
    raise ModuleContainsSpace
  }
  if module_name.contains("//") {
    raise ModuleHasEmptySegment
  }
  for ch in module_name {
    if !module_name_char_is_valid(ch) {
      raise ModuleHasUnsupportedCharacter(character=ch)
    }
  }
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
fn validate_title(title : String) -> Unit raise NewProjectInputError {
  if title.trim().is_empty() {
    raise EmptyTitle
  }
}

///|
fn validate_target_dir(target_dir : String) -> Unit raise NewProjectInputError {
  if target_dir.trim().is_empty() {
    raise EmptyProjectDirectory
  }
}

///|
fn target_dir_is_empty(target_dir : String) -> Bool raise NewProjectTargetError {
  if !path_exists(target_dir) {
    return true
  }
  if !path_is_dir(target_dir) {
    raise NotDirectory(path=target_dir)
  }
  let entries = @mbfs.read_dir(target_dir) catch {
    err =>
      raise ReadDirectory(
        path=target_dir,
        detail=@debug.render(@debug.to_repr(err)),
      )
  }
  entries.length() == 0
}

///|
fn validate_target_dir_for_write(
  target_dir : String,
) -> Unit raise NewProjectTargetError {
  let moon_mod_path = new_path_join(target_dir, "moon.mod")
  if path_exists(moon_mod_path) {
    raise ContainsMoonModule(path=target_dir)
  }
  if !target_dir_is_empty(target_dir) {
    raise NotEmpty(path=target_dir)
  }
}
