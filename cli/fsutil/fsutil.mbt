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
/// Converts portable separators before entering the host path API.
fn host_path(path : String) -> @path.Path {
  if @path.sep == '\\' {
    path.replace_all(old="/", new="\\")
  } else {
    path
  }
}

///|
/// Joins `base` and `child` with the host platform's path rules.
pub fn path_join(base : String, child : String) -> String {
  if base == "" {
    child
  } else if child == "" {
    base
  } else {
    host_path(base).join(host_path(child)).to_string()
  }
}

///|
/// Returns the parent directory of `path` using the host platform's path rules.
pub fn path_parent(path : String) -> String {
  host_path(path).dirname().to_string()
}

///|
/// Returns whether `path` is absolute on the host platform.
pub fn path_is_absolute(path : String) -> Bool {
  host_path(path).is_absolute()
}

///|
/// Resolves `path` against `base` and normalizes `.`/`..` segments.
pub fn resolve_path(base : String, path : String) -> String {
  let candidate = host_path(path)
  if candidate.is_absolute() {
    candidate.resolve().to_string()
  } else {
    host_path(base).join(candidate).resolve().to_string()
  }
}

///|
/// Computes the host-native path from `base` to `path` after resolving both.
pub fn relative_path(base : String, path : String) -> String {
  let base_path = host_path(base).resolve()
  let candidate = host_path(path).resolve()
  candidate.relative(base=base_path).to_string()
}

///|
/// Returns whether `candidate` is `root` or one of its lexical descendants.
pub fn path_is_within(root : String, candidate : String) -> Bool {
  let relative = relative_path(root, candidate)
  let relative_path = host_path(relative)
  !relative_path.is_absolute() &&
  relative != ".." &&
  !relative.has_prefix(".." + @path.sep.to_string())
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
