///|
/// Wraps a string as the native path abstraction used by this package.
fn native_path(path : String) -> @mbpath.Path {
  path
}

///|
/// Rewrites separators when the current platform expects backslashes.
fn prepare_native_path(path : String) -> String {
  if @mbpath.sep != '\\' {
    return path
  }
  let builder = StringBuilder::new(size_hint=path.length())
  for _, ch in path {
    builder.write_char(if ch == '/' { '\\' } else { ch })
  }
  builder.to_string()
}

///|
/// Returns the last path segment, optionally trimming a matching suffix.
fn basename_path(path : String, suffix? : String? = None) -> String {
  let normalized = normalize_path(path)
  let name = native_path(normalized).basename().to_owned()
  match suffix {
    Some(suffix) =>
      if suffix != "" &&
        name.length() >= suffix.length() &&
        name.has_suffix(suffix) {
        name[:name.length() - suffix.length()].to_owned()
      } else {
        name
      }
    None => name
  }
}

///|
/// Returns the parent directory portion of a path.
fn dirname_path(path : String) -> String {
  let normalized = normalize_path(path)
  native_path(normalized).dirname().to_string()
}

///|
/// Returns the file extension portion of a path.
fn extname_path(path : String) -> String {
  let normalized = normalize_path(path)
  native_path(normalized).extname().to_owned()
}

///|
/// Returns whether a path is absolute on the current platform.
fn is_absolute_path(path : String) -> Bool {
  native_path(prepare_native_path(path)).is_absolute()
}

///|
/// Joins two path segments using the platform-native path rules.
fn join_paths(left : String, right : String) -> String {
  native_path(prepare_native_path(left))
  .join(prepare_native_path(right))
  .to_string()
}

///|
/// Joins many path segments while skipping empty entries.
fn join_many_paths(paths : Array[String]) -> String {
  let mut result = ""
  let mut found = false
  for path in paths {
    if path != "" {
      if found {
        result = join_paths(result, path)
      } else {
        result = path
        found = true
      }
    }
  }
  if found {
    normalize_path(result)
  } else {
    "."
  }
}

///|
/// Normalizes redundant path separators and dot segments.
fn normalize_path(path : String) -> String {
  native_path(prepare_native_path(path)).normalize().to_string()
}

///|
/// Computes the relative path from `base` to `path`.
fn relative_path(path : String, base : String) -> String {
  native_path(prepare_native_path(path))
  .relative(base=prepare_native_path(base))
  .to_string()
}

///|
/// Resolves a path against the current working directory.
fn resolve_path(path : String) -> String {
  native_path(prepare_native_path(path)).resolve().to_string()
}

///|
/// Joins many path segments and resolves the result to an absolute path.
fn resolve_many_paths(paths : Array[String]) -> String {
  if paths.length() == 0 {
    return resolve_path(".")
  }
  let joined = join_many_paths(paths)
  resolve_path(joined)
}
