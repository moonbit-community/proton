///|
/// Returns whether `path` exists on the filesystem.
pub async fn path_exists(path : String) -> Bool {
  @async_fs.exists(path)
}

///|
/// Returns whether `path` exists and is a directory.
pub async fn path_is_dir(path : String) -> Bool {
  if !@async_fs.exists(path) {
    return false
  }
  @async_fs.kind(path) is Directory
}

///|
/// Returns whether `path` exists and is a regular file.
pub async fn path_is_file(path : String) -> Bool {
  if !@async_fs.exists(path) {
    return false
  }
  @async_fs.kind(path) is Regular
}

///|
/// Joins `base` and `child` with the platform separator. An empty `base` or
/// `child` yields the other component, and no extra separator is added when
/// `base` already ends in one.
pub fn path_join(base : String, child : String) -> String {
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
/// Returns the parent directory of `path`, stripping one trailing separator
/// first. When `path` has no parent (a bare relative name or a single-level
/// absolute path like `/a`), the input is returned unchanged, so callers
/// detect the top of a walk-up loop with `parent == path`. The filesystem
/// root itself is the one exception: `path_parent("/")` returns `""`.
pub fn path_parent(path : String) -> String {
  let normalized = if path.has_suffix("\\") || path.has_suffix("/") {
    path.unsafe_substring(start=0, end=path.length() - 1)
  } else {
    path
  }
  let slash = normalized.rev_find("/")
  let backslash = normalized.rev_find("\\")
  let index = match (slash, backslash) {
    (Some(a), Some(b)) => Some(if a > b { a } else { b })
    (Some(a), None) => Some(a)
    (None, Some(b)) => Some(b)
    (None, None) => None
  }
  match index {
    Some(index) if index > 0 =>
      normalized.unsafe_substring(start=0, end=index).to_string()
    _ => normalized.to_string()
  }
}

///|
/// Returns whether `path` is absolute on the current platform. On Windows
/// this accepts drive-letter paths with either separator (`C:/x`, `C:\x`)
/// and rooted paths (`\x`, `/x`, `\\server\share`); on POSIX only a leading
/// `/` qualifies, so `assets/http:/x` stays relative.
pub fn path_is_absolute(path : String) -> Bool {
  if @path.sep == '\\' {
    if path.has_prefix("\\") || path.has_prefix("/") {
      return true
    }
    guard path.length() >= 3 else { return false }
    let drive = path[0]
    ((drive >= 65 && drive <= 90) || (drive >= 97 && drive <= 122)) &&
    path[1] == ':' &&
    (path[2] == '\\' || path[2] == '/')
  } else {
    path.has_prefix("/")
  }
}

///|
/// Resolves `path` against `base` and normalizes `.`/`..` segments. On
/// Windows, `\` in a relative child is rewritten to `/` before joining:
/// the moonbitlang/x win32 path lexer misclassifies backslash relative
/// paths that start with `.` or a digit (`.\target\x`,
/// `38_app\commands.mbt`) as absolute or prefixed, which would drop `base`
/// or skip absolutization. Absolute inputs the lexer cannot classify
/// (`C:/x`) are returned unchanged. On POSIX both inputs are used verbatim
/// so legitimate backslash file names are preserved.
pub fn resolve_path(base : String, path : String) -> String {
  if path_is_absolute(path) {
    let candidate : @path.Path = path
    if @path.sep == '\\' && !candidate.is_absolute() {
      path
    } else {
      candidate.resolve().to_string()
    }
  } else {
    let path = if @path.sep == '\\' {
      path.replace_all(old="\\", new="/")
    } else {
      path
    }
    @path.Path(base).join(path).resolve().to_string()
  }
}

///|
/// Walks up from `start` looking for `moon.work` or `moon.mod`; returns the
/// first directory containing either marker, or `start` when none is found.
pub async fn find_project_root_from(start : String) -> String {
  for dir = start; dir != ""; {
    if path_exists(path_join(dir, "moon.work")) ||
      path_exists(path_join(dir, "moon.mod")) {
      return dir
    }
    let parent = path_parent(dir)
    if parent == dir {
      return start
    }
    continue parent
  }
  start
}
