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
async fn find_project_root_marker(start : String) -> (String, String?)? {
  let moon_mod_path = @fsutil.path_join(start, "moon.mod")
  if @fsutil.path_exists(moon_mod_path) {
    return Some((start, Some(moon_mod_path)))
  }
  if @fsutil.path_exists(@fsutil.path_join(start, "moon.work")) {
    return Some((start, None))
  }
  let parent = @fsutil.path_parent(start)
  if parent == start {
    None
  } else {
    find_project_root_marker(parent)
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
async fn discover_project(cwd : String) -> ProjectDoctorInfo {
  let cwd = @path.Path(cwd).resolve().to_string()
  let discovered_moon_proton_path = find_up(cwd, "moon.proton")
  let discovered_app_json_path = find_up(cwd, "app.json")
  let fallback_root = match
    (discovered_moon_proton_path, discovered_app_json_path) {
    (Some(path), _) => {
      let parent = @fsutil.path_parent(path)
      if parent == path {
        cwd
      } else {
        parent
      }
    }
    (_, Some(path)) => {
      let parent = @fsutil.path_parent(path)
      if parent == path {
        cwd
      } else {
        parent
      }
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
      let app_package = @fsutil.path_join(
        @fsutil.path_join(root, "app"),
        "moon.pkg",
      )
      if @fsutil.path_exists(app_package) {
        Some(app_package)
      } else {
        None
      }
    }
    None => None
  }
  let package_dir = match moon_pkg_path {
    Some(path) => {
      let parent = @fsutil.path_parent(path)
      if parent == path {
        cwd
      } else {
        parent
      }
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
