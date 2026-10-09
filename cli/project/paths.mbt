///|
fn validate_project_paths(
  config : @proton_config.AppConfig,
) -> Unit raise @proton_config.AppConfigError {
  if config.backend is Some(backend) {
    validate_relative_project_path(backend.path, "backend.path")
  }
  if config.frontend is Some(frontend) {
    for (value, field) in [(frontend.path, "path"), (frontend.dist, "dist")] {
      if value is Some(value) {
        validate_relative_project_path(value, "frontend." + field)
      }
    }
  }
  if config.package_config is Some(package_config) {
    validate_relative_project_path(package_config.output, "package.output")
    for
      (paths, field) in [
        (package_config.icons, "icons"),
        (package_config.resources, "resources"),
      ] {
      for path in paths {
        validate_relative_project_path(path, "package." + field)
      }
    }
    validate_sign_paths(package_config.sign, "package.sign")
    let platforms = package_config.platforms
    for
      (value, platform) in [
        (platforms.macos, "macos"),
        (platforms.windows, "windows"),
        (platforms.linux, "linux"),
      ] {
      if value is Some(value) {
        let label = "package.platforms." + platform
        for path in value.resources {
          validate_relative_project_path(path, label + ".resources")
        }
        validate_sign_paths(value.sign, label + ".sign")
      }
    }
  }
}

///|
fn validate_sign_paths(
  sign : @proton_config.SignConfig?,
  label : String,
) -> Unit raise @proton_config.AppConfigError {
  if sign is Some(sign) {
    for path in sign.binaries {
      validate_relative_project_path(path, label + ".binaries")
    }
  }
}

///|
fn validate_relative_project_path(
  path : String,
  label : String,
) -> Unit raise @proton_config.AppConfigError {
  let field = if label.has_prefix("proton.project.json.") {
    label
  } else {
    "proton.project.json." + label
  }
  guard !project_path_has_root(path) else {
    raise @proton_config.InvalidField(
      path=field,
      expectation="must be a relative path; absolute paths and drive prefixes are not allowed",
    )
  }
  guard !path.contains("\\") else {
    raise @proton_config.InvalidField(
      path=field,
      expectation="must use '/' separators; backslashes are not allowed in portable project paths",
    )
  }
}

///|
fn project_path_has_root(path : String) -> Bool {
  if path.has_prefix("/") || path.has_prefix("\\") {
    return true
  }
  guard path.length() >= 2 else { return false }
  let drive = path[0]
  ((drive >= 'A' && drive <= 'Z') || (drive >= 'a' && drive <= 'z')) &&
  path[1] == ':'
}
