///|
fn find_project_root_from(start : String) -> String {
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

///|
fn project_root(cwd : String) -> Result[String, CefError] {
  if cwd != "" && cwd != "." {
    return Ok(find_project_root_from(cwd))
  }
  match @env.current_dir() {
    Some(cwd) => Ok(find_project_root_from(cwd))
    None => Err(CefError::CommandError("Failed to read current directory"))
  }
}
