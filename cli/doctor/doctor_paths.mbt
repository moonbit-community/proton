///|
async fn doctor_path_exists(path : String) -> Bool noraise {
  @async_fs.exists(path) catch {
    _ => false
  }
}

///|
async fn doctor_path_is_file(path : String) -> Bool noraise {
  (@async_fs.kind(path) is Regular) catch {
    _ => false
  }
}

///|
async fn doctor_path_is_dir(path : String) -> Bool noraise {
  (@async_fs.kind(path) is Directory) catch {
    _ => false
  }
}

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
async fn find_up(start : String, file_name : String) -> String? noraise {
  let candidate = path_join(start, file_name)
  if doctor_path_exists(candidate) {
    Some(candidate)
  } else {
    match path_parent(start) {
      Some(parent) => find_up(parent, file_name)
      None => None
    }
  }
}

///|
async fn find_project_root_marker(start : String) -> (String, String?)? noraise {
  let moon_mod_path = path_join(start, "moon.mod")
  if doctor_path_exists(moon_mod_path) {
    return Some((start, Some(moon_mod_path)))
  }
  if doctor_path_exists(path_join(start, "moon.work")) {
    return Some((start, None))
  }
  match path_parent(start) {
    Some(parent) => find_project_root_marker(parent)
    None => None
  }
}

///|
fn path_text_equal(
  left : String,
  right : String,
  case_sensitive~ : Bool,
) -> Bool {
  if case_sensitive {
    left == right
  } else {
    left.equal_ignore_ascii_case(right)
  }
}

///|
fn path_text_has_prefix(
  value : String,
  prefix : String,
  case_sensitive~ : Bool,
) -> Bool {
  if value.length() < prefix.length() {
    return false
  }
  path_text_equal(
    value.unsafe_substring(start=0, end=prefix.length()),
    prefix,
    case_sensitive~,
  )
}

///|
fn path_is_within_root(root : String, path : String) -> Bool {
  let root = @path.Path(root).resolve().to_string()
  let resolved = @path.Path(path).resolve().to_string()
  let separator = @path.sep.to_string()
  let prefix = if root.has_suffix(separator) { root } else { root + separator }
  let case_sensitive = @path.sep != '\\'
  path_text_equal(resolved, root, case_sensitive~) ||
  path_text_has_prefix(resolved, prefix, case_sensitive~)
}

///|
fn path_option_within_root(root : String, path : String?) -> String? {
  match path {
    Some(path) if path_is_within_root(root, path) => Some(path)
    _ => None
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
async fn discover_project(cwd : String) -> ProjectDoctorInfo noraise {
  let cwd = @path.Path(cwd).resolve().to_string()
  let discovered_moon_proton_path = find_up(cwd, "moon.proton")
  let discovered_app_json_path = find_up(cwd, "app.json")
  let fallback_root = match
    (discovered_moon_proton_path, discovered_app_json_path) {
    (Some(path), _) =>
      match path_parent(path) {
        Some(parent) => parent
        None => cwd
      }
    (_, Some(path)) =>
      match path_parent(path) {
        Some(parent) => parent
        None => cwd
      }
    _ => cwd
  }
  let (root, moon_mod_path) = match find_project_root_marker(cwd) {
    Some(marker) => marker
    None => (fallback_root, None)
  }
  let moon_proton_path = path_option_within_root(
    root, discovered_moon_proton_path,
  )
  let app_json_path = path_option_within_root(root, discovered_app_json_path)
  let discovered_moon_pkg_path = path_option_within_root(
    root,
    find_up(cwd, "moon.pkg"),
  )
  let mode = project_mode(moon_proton_path, app_json_path, moon_mod_path)
  let moon_pkg_path = match discovered_moon_pkg_path {
    Some(path) => Some(path)
    None if mode == AppProject => {
      let app_package = path_join(path_join(root, "app"), "moon.pkg")
      if doctor_path_exists(app_package) {
        Some(app_package)
      } else {
        None
      }
    }
    None => None
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
    mode,
    moon_mod_path,
    moon_pkg_path,
    moon_proton_path,
    app_json_path,
  }
}
