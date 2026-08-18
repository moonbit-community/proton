///|
/// Failures while resolving framework-owned application paths.
pub(all) suberror AppPathError {
  InvalidIdentifier(identifier~ : String)
  MissingHomeDirectory(platform~ : String)
  ResourceDirUnavailable
  PlatformProbe(@native.NativeError)
} derive(Debug, Eq)

///|
pub extend AppPathError with Eq::{not_equal, equal}

///|
pub extend AppPathError with Debug::{to_repr}

///|
pub fn AppPathError::message(self : AppPathError) -> String {
  match self {
    InvalidIdentifier(identifier~) =>
      "invalid application identifier: " + identifier
    MissingHomeDirectory(platform~) =>
      "cannot resolve the application data directory on " + platform
    ResourceDirUnavailable =>
      "cannot resolve the application resource directory without proton.project.json"
    PlatformProbe(error) =>
      "cannot determine the Proton platform: " + error.message()
  }
}

///|
/// Resolves the absolute application resource directory.
///
/// This follows Proton's implicit project config discovery. In development it
/// is the directory containing `proton.project.json`; in a packaged application
/// it is the directory into which `bundle.resources` are copied, such as
/// `Contents/Resources` in a macOS application bundle.
pub fn resource_dir() -> String raise AppPathError {
  match implicit_config_path() {
    Some(path) => resource_dir_from_config_path(path)
    None => raise ResourceDirUnavailable
  }
}

///|
fn resource_dir_from_config_path(path : String) -> String {
  let config : @mbpath.Path = path
  config.resolve().dirname().to_string()
}

///|
/// Resolves the stable per-application directory for native persistent data.
///
/// The identifier should match the packaged bundle/application identifier.
/// This function resolves the path but does not create the directory.
pub fn app_data_dir(identifier : String) -> String raise AppPathError {
  let info = @native.runtime_info() catch {
    error => raise PlatformProbe(error)
  }
  let platform = info.platform
  app_data_dir_for_platform(
    platform,
    identifier,
    @env.get_env_var("HOME"),
    @env.get_env_var("LOCALAPPDATA"),
    @env.get_env_var("XDG_DATA_HOME"),
  )
}

///|
fn browser_data_dir(identifier : String) -> String raise AppPathError {
  @mbpath.Path(app_data_dir(identifier)).join("browser").normalize().to_string()
}

///|
fn app_data_dir_for_platform(
  platform : String,
  identifier : String,
  home : String?,
  local_app_data : String?,
  xdg_data_home : String?,
) -> String raise AppPathError {
  validate_app_identifier(identifier)
  let base = match platform {
    "macos" =>
      @mbpath.Path(require_path_base(home, platform)).join(
        "Library/Application Support",
      )
    "windows" => @mbpath.Path(require_path_base(local_app_data, platform))
    "linux" =>
      match non_empty_path(xdg_data_home) {
        Some(path) => @mbpath.Path(path)
        None =>
          @mbpath.Path(require_path_base(home, platform)).join(".local/share")
      }
    _ => raise MissingHomeDirectory(platform~)
  }
  base.join(identifier).normalize().to_string()
}

///|
fn validate_app_identifier(identifier : String) -> Unit raise AppPathError {
  let value = identifier.trim().to_owned()
  if value == "" ||
    value == "." ||
    value == ".." ||
    value.contains("/") ||
    value.contains("\\") ||
    value.contains("\u0000") {
    raise InvalidIdentifier(identifier~)
  }
}

///|
fn non_empty_path(value : String?) -> String? {
  match value {
    Some(path) => {
      let path = path.trim().to_owned()
      if path == "" {
        None
      } else {
        Some(path)
      }
    }
    None => None
  }
}

///|
fn require_path_base(
  value : String?,
  platform : String,
) -> String raise AppPathError {
  match non_empty_path(value) {
    Some(path) => path
    None => raise MissingHomeDirectory(platform~)
  }
}
