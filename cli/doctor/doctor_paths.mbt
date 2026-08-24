///|
async fn discover_project(cwd : String) -> ProjectDoctorInfo? {
  let cwd = @path.Path(cwd).resolve().to_string()
  let config_path = @fsutil.path_join(cwd, "proton.project.json")
  if @fsutil.path_exists(config_path) {
    Some({ root: cwd, config_path, })
  } else {
    None
  }
}
