///|
async fn project_root(cwd : String) -> String {
  if cwd != "" && cwd != "." {
    return @fsutil.find_project_root_from(cwd)
  }
  match @env.current_dir() {
    Some(cwd) => @fsutil.find_project_root_from(cwd)
    None => raise CurrentDirectoryUnavailable
  }
}
