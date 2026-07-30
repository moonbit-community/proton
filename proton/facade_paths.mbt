///|
/// Failures while resolving framework-owned application paths.
pub(all) suberror AppPathError {
  InvalidIdentifier(identifier~ : String)
  MissingHomeDirectory(platform~ : String)
  PlatformProbe(@native.NativeError)
} derive(Debug, Eq)

///|
pub fn AppPathError::message(self : AppPathError) -> String {
  match self {
    InvalidIdentifier(identifier~) =>
      "invalid application identifier: " + identifier
    MissingHomeDirectory(platform~) =>
      "cannot resolve the application data directory on " + platform
    PlatformProbe(error) =>
      "cannot determine the Proton platform: " + error.message()
  }
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
