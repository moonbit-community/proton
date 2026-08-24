///|
/// Failures while resolving framework-owned application paths.
pub(all) suberror AppPathError {
  InvalidIdentifier(identifier~ : String)
  MissingHomeDirectory(platform~ : String)
  PlatformProbe(status~ : Int, detail~ : String)
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
    PlatformProbe(status~, detail~) =>
      "cannot determine the Proton platform (" +
      status.to_string() +
      "): " +
      detail
  }
}

///|
/// Resolves the absolute application resource directory.
///
/// `proton_cli dev` supplies the project resource directory explicitly. A
/// packaged application resolves the package resource directory beside its
/// executable. Directly launched code uses the current working directory.
pub fn resource_dir() -> String {
  runtime_resource_dir()
}

///|
fn runtime_resource_dir() -> String {
  match @env.get_env_var("PROTON_RESOURCE_DIR") {
    Some(value) if value.trim().to_owned() != "" => {
      let path : @mbpath.Path = value.trim().to_owned()
      return path.resolve().to_string()
    }
    _ => ()
  }
  match packaged_resource_dir() {
    Some(path) => path
    None => {
      let current : @mbpath.Path = "."
      current.resolve().to_string()
    }
  }
}

///|
fn packaged_resource_dir() -> String? {
  let args = @env.args()
  guard args.length() > 0 else { return None }
  let executable : @mbpath.Path = args[0]
  let executable_dir = executable.resolve().dirname()
  let candidate = if @mbpath.sep == '\\' {
    executable_dir.join("Resources").normalize()
  } else {
    executable_dir.join("../Resources").normalize()
  }
  let packaged = @mbfs.is_file(
    candidate.join("proton-package.json").to_string(),
  ) catch {
    _ => false
  }
  guard packaged else { return None }
  Some(candidate.to_string())
}

///|
/// Resolves the stable per-application directory for native persistent data.
///
/// The identifier should match the packaged bundle/application identifier.
/// This function resolves the path but does not create the directory.
pub fn app_data_dir(identifier : String) -> String raise AppPathError {
  let info = @native.runtime_info() catch {
    error => raise PlatformProbe(status=error.status(), detail=error.message())
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
