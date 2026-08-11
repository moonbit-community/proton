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
  match find_up(cwd, "moon.proton") {
    Some(config_path) =>
      Some({ root: @fsutil.path_parent(config_path), config_path })
    None => None
  }
}

///|
fn runtime_library_relative_path(platform_id : String) -> String? {
  match platform_id {
    "win32-x64" => Some("bin\\proton.dll")
    "darwin-arm64" | "darwin-x64" => Some("lib/libproton.dylib")
    "linux-x64" => Some("lib/libproton.so")
    _ => None
  }
}

///|
fn runtime_helper_relative_path(platform_id : String) -> String {
  if platform_id == "win32-x64" {
    "bin\\cef_process.exe"
  } else {
    "bin/cef_process"
  }
}
