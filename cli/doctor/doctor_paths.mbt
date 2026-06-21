///|
fn path_join(base : String, name : String) -> String {
  if base == "" || base == "." {
    name
  } else if base.has_suffix("\\") || base.has_suffix("/") {
    base + name
  } else {
    base + "\\" + name
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
  app_json_path : String?,
  moon_mod_path : String?,
  proton_cli_json_path : String?,
) -> ProjectMode {
  match (app_json_path, proton_cli_json_path, moon_mod_path) {
    (Some(_), _, _) | (_, Some(_), _) => AppProject
    (_, _, Some(_)) => MoonPackage
    _ => PlainDirectory
  }
}

///|
fn discover_project(cwd : String) -> ProjectDoctorInfo {
  let proton_cli_json_path = if @mbfs.path_exists(
      path_join(cwd, "proton.cli.json"),
    ) {
    Some(path_join(cwd, "proton.cli.json"))
  } else {
    None
  }
  let app_json_path = find_up(cwd, "app.json")
  let moon_mod_path = find_up(cwd, "moon.mod")
  let moon_pkg_path = match find_up(cwd, "moon.pkg") {
    Some(path) => Some(path)
    None => None
  }
  let root = match (proton_cli_json_path, app_json_path, moon_mod_path) {
    (Some(_), _, _) => cwd
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
    mode: project_mode(app_json_path, moon_mod_path, proton_cli_json_path),
    moon_mod_path,
    moon_pkg_path,
    app_json_path,
    proton_cli_json_path,
  }
}
