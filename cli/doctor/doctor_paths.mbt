///|
async fn find_up(start : String, file_name : String) -> String? {
  let candidate = @fsutil.path_join(start, file_name)
  if @fsutil.path_exists(candidate) {
    Some(candidate)
  } else {
    let parent = @fsutil.path_parent(start)
    if parent == start {
      None
    } else {
      find_up(parent, file_name)
    }
  }
}

///|
async fn discover_project(cwd : String) -> ProjectDoctorInfo? {
  let cwd = @path.Path(cwd).resolve().to_string()
  match find_up(cwd, "proton.project.json") {
    Some(config_path) =>
      Some({ root: @fsutil.path_parent(config_path), config_path })
    None => None
  }
}
