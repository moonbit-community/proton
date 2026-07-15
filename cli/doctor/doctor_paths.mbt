///|
fn path_join(base : String, name : String) -> String {
  if base == "" || base == "." {
    name
  } else if base.has_suffix("\\") || base.has_suffix("/") {
    base + name
  } else {
    base + @path.sep.to_string() + name
  }
}

///|
fn path_parent(path : String) -> String? {
  let normalized = if path.has_suffix("\\") || path.has_suffix("/") {
    path.unsafe_substring(start=0, end=path.length() - 1)
  } else {
    path
  }
  match normalized.rev_find("\\") {
    Some(index) if index > 0 =>
      Some(normalized.unsafe_substring(start=0, end=index))
    _ =>
      match normalized.rev_find("/") {
        Some(index) if index > 0 =>
          Some(normalized.unsafe_substring(start=0, end=index))
        _ => None
      }
  }
}

///|
fn find_up(start : String, file_name : String) -> String? {
  let candidate = path_join(start, file_name)
  if @mbfs.path_exists(candidate) {
    Some(candidate)
  } else {
    match path_parent(start) {
      Some(parent) => find_up(parent, file_name)
      None => None
    }
  }
}

///|
fn project_mode(
  moon_proton_path : String?,
  app_json_path : String?,
  moon_mod_path : String?,
) -> ProjectMode {
  match (moon_proton_path, app_json_path, moon_mod_path) {
    (Some(_), _, _) | (_, Some(_), _) => AppProject
    (_, _, Some(_)) => MoonPackage
    _ => PlainDirectory
  }
}

///|
fn discover_project(cwd : String) -> ProjectDoctorInfo {
  let moon_proton_path = find_up(cwd, "moon.proton")
  let app_json_path = find_up(cwd, "app.json")
  let moon_mod_path = find_up(cwd, "moon.mod")
  let moon_pkg_path = match find_up(cwd, "moon.pkg") {
    Some(path) => Some(path)
    None => None
  }
  let root = match (moon_proton_path, app_json_path, moon_mod_path) {
    (Some(path), _, _) =>
      match path_parent(path) {
        Some(parent) => parent
        None => cwd
      }
    (_, Some(path), _) =>
      match path_parent(path) {
        Some(parent) => parent
        None => cwd
      }
    (_, _, Some(path)) =>
      match path_parent(path) {
        Some(parent) => parent
        None => cwd
      }
    _ => cwd
  }
  let package_dir = match moon_pkg_path {
    Some(path) =>
      match path_parent(path) {
        Some(parent) => parent
        None => cwd
      }
    None => cwd
  }
  {
    root,
    package_dir,
    mode: project_mode(moon_proton_path, app_json_path, moon_mod_path),
    moon_mod_path,
    moon_pkg_path,
    moon_proton_path,
    app_json_path,
  }
}
