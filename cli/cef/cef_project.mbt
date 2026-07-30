///|
async fn find_project_root_from(start : String) -> String {
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
async fn project_root(cwd : String) -> String {
  if cwd != "" && cwd != "." {
    return find_project_root_from(cwd)
  }
  match @env.current_dir() {
    Some(cwd) => find_project_root_from(cwd)
    None => raise CurrentDirectoryUnavailable
  }
}
