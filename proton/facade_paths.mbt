///|
/// Failures while resolving framework-owned application paths.
pub(all) suberror AppPathError {
  MissingApplicationIdentifier
  InvalidIdentifier(identifier~ : String)
  MissingHomeDirectory(platform~ : String)
  MissingEnvironmentPath(name~ : String, platform~ : String)
  MissingExecutablePath
  UnsupportedPath(kind~ : String, platform~ : String)
  SystemPath(kind~ : String, status~ : Int, detail~ : String)
  PlatformProbe(status~ : Int, detail~ : String)
} derive(Debug, Eq)

///|
pub extend AppPathError with Eq::{not_equal, equal}

///|
pub extend AppPathError with Debug::{to_repr}

///|
pub fn AppPathError::message(self : AppPathError) -> String {
  match self {
    MissingApplicationIdentifier => "application identifier is not configured"
    InvalidIdentifier(identifier~) =>
      "invalid application identifier: " + identifier
    MissingHomeDirectory(platform~) =>
      "cannot resolve the home directory on " + platform
    MissingEnvironmentPath(name~, platform~) =>
      "cannot resolve " + name + " on " + platform
    MissingExecutablePath => "cannot resolve the application executable path"
    UnsupportedPath(kind~, platform~) =>
      "application path " + kind + " is not available on " + platform
    SystemPath(kind~, status~, detail~) =>
      "cannot resolve application path " +
      kind +
      " (" +
      status.to_string() +
      "): " +
      detail
    PlatformProbe(status~, detail~) =>
      "cannot determine the Proton platform (" +
      status.to_string() +
      "): " +
      detail
  }
}

///|
/// Standard application paths corresponding to Electron's high-frequency
/// `app.getPath` names.
pub(all) enum AppPathKind {
  Home
  AppData
  UserData
  SessionData
  Temp
  Executable
  Logs
  Assets
  Module
  Desktop
  Documents
  Downloads
  Music
  Pictures
  Videos
  Recent
} derive(Debug, Eq)

///|
pub extend AppPathKind with Eq::{not_equal, equal}

///|
pub extend AppPathKind with Debug::{to_repr}

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
/// Returns the application resource root, corresponding to Electron's
/// `app.getAppPath()`.
pub fn app_path() -> String {
  runtime_resource_dir()
}

///|
/// Returns whether this process is running from a Proton package.
pub fn is_packaged() -> Bool {
  packaged_application_manifest_path() is Some(_)
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
  packaged_application_manifest_path().map(path => {
    packaged_resource_dir_from_manifest(path, @mbpath.sep == '\\')
  })
}

///|
fn packaged_resource_dir_from_manifest(path : String, windows : Bool) -> String {
  let manifest : @mbpath.Path = path
  let root = manifest.dirname()
  if windows {
    root.join("Resources").normalize().to_string()
  } else {
    root.normalize().to_string()
  }
}

///|
fn packaged_application_manifest_path() -> String? {
  let args = @env.args()
  guard args.length() > 0 else { return None }
  let executable : @mbpath.Path = args[0]
  let executable = executable.resolve()
  let executable_dir = executable.dirname()
  let candidates = if @mbpath.sep == '\\' {
    [executable_dir.join("proton-package.json")]
  } else {
    [
      executable_dir.join("../Resources/proton-package.json"),
      executable_dir
      .join("../share")
      .join(executable.basename().to_owned())
      .join("proton-package.json"),
    ]
  }
  for candidate in candidates {
    let candidate = candidate.normalize()
    let packaged = @mbfs.is_file(candidate.to_string()) catch { _ => false }
    if packaged {
      return Some(candidate.to_string())
    }
  }
  None
}

///|
/// Resolves the stable directory for this application's persistent native data.
/// This function resolves the path but does not create the directory.
pub fn App::data_dir(self : App) -> String raise AppPathError {
  app_data_dir_for_identifier(self.application_identifier())
}

///|
/// Resolves a standard application path.
///
/// `UserData`, `SessionData`, and `Logs` use the application's stable
/// reverse-DNS identifier instead of its display name so package renames do not
/// move persisted state.
pub fn App::path(self : App, kind : AppPathKind) -> String raise AppPathError {
  let info = @native.runtime_info() catch {
    error => raise PlatformProbe(status=error.status(), detail=error.message())
  }
  let platform = info.platform
  match kind {
    Home =>
      home_dir_for_platform(
        platform,
        @env.get_env_var("HOME"),
        @env.get_env_var("USERPROFILE"),
      )
    AppData =>
      application_data_root_for_platform(
        platform,
        @env.get_env_var("HOME"),
        @env.get_env_var("APPDATA"),
        @env.get_env_var("XDG_CONFIG_HOME"),
      )
    UserData =>
      app_data_dir_for_platform(
        platform,
        self.application_identifier(),
        @env.get_env_var("HOME"),
        @env.get_env_var("LOCALAPPDATA"),
        @env.get_env_var("XDG_DATA_HOME"),
      )
    SessionData =>
      @mbpath.Path(
        app_data_dir_for_platform(
          platform,
          self.application_identifier(),
          @env.get_env_var("HOME"),
          @env.get_env_var("LOCALAPPDATA"),
          @env.get_env_var("XDG_DATA_HOME"),
        ),
      )
      .join("browser")
      .normalize()
      .to_string()
    Temp =>
      temp_dir_for_platform(
        platform,
        @env.get_env_var("TMPDIR"),
        @env.get_env_var("TEMP"),
        @env.get_env_var("TMP"),
      )
    Executable => executable_path()
    Logs =>
      app_log_dir_for_platform(
        platform,
        self.application_identifier(),
        @env.get_env_var("HOME"),
        @env.get_env_var("LOCALAPPDATA"),
        @env.get_env_var("XDG_STATE_HOME"),
      )
    Assets => {
      guard platform == "windows" || platform == "linux" else {
        raise UnsupportedPath(kind="assets", platform~)
      }
      executable_dir()
    }
    Module => executable_path()
    Desktop => resolve_system_path(@native.SystemPathKind::Desktop, "desktop")
    Documents =>
      resolve_system_path(@native.SystemPathKind::Documents, "documents")
    Downloads =>
      resolve_system_path(@native.SystemPathKind::Downloads, "downloads")
    Music => resolve_system_path(@native.SystemPathKind::Music, "music")
    Pictures =>
      resolve_system_path(@native.SystemPathKind::Pictures, "pictures")
    Videos => resolve_system_path(@native.SystemPathKind::Videos, "videos")
    Recent => {
      guard platform == "windows" else {
        raise UnsupportedPath(kind="recent", platform~)
      }
      resolve_system_path(@native.SystemPathKind::Recent, "recent")
    }
  }
}

///|
fn executable_path() -> String raise AppPathError {
  guard @env.args().get(0) is Some(executable) else {
    raise MissingExecutablePath
  }
  let path : @mbpath.Path = executable
  path.resolve().to_string()
}

///|
fn executable_dir() -> String raise AppPathError {
  let executable : @mbpath.Path = executable_path()
  executable.dirname().normalize().to_string()
}

///|
fn resolve_system_path(
  kind : @native.SystemPathKind,
  label : String,
) -> String raise AppPathError {
  @native.system_path(kind) catch {
    error =>
      raise SystemPath(
        kind=label,
        status=error.status(),
        detail=error.message(),
      )
  }
}

///|
fn home_dir_for_platform(
  platform : String,
  home : String?,
  user_profile : String?,
) -> String raise AppPathError {
  let base = match platform {
    "windows" => user_profile
    "macos" | "linux" => home
    _ => None
  }
  match non_empty_path(base) {
    Some(path) => @mbpath.Path(path).normalize().to_string()
    None => raise MissingHomeDirectory(platform~)
  }
}

///|
fn application_data_root_for_platform(
  platform : String,
  home : String?,
  app_data : String?,
  xdg_config_home : String?,
) -> String raise AppPathError {
  let root = match platform {
    "macos" =>
      @mbpath.Path(require_path_base(home, platform)).join(
        "Library/Application Support",
      )
    "windows" =>
      @mbpath.Path(
        require_environment_path(app_data, "application data", platform),
      )
    "linux" =>
      match non_empty_path(xdg_config_home) {
        Some(path) => @mbpath.Path(path)
        None => @mbpath.Path(require_path_base(home, platform)).join(".config")
      }
    _ => raise MissingEnvironmentPath(name="application data", platform~)
  }
  root.normalize().to_string()
}

///|
fn temp_dir_for_platform(
  platform : String,
  tmpdir : String?,
  temp : String?,
  tmp : String?,
) -> String raise AppPathError {
  let candidates = match platform {
    "windows" => [temp, tmp]
    "macos" | "linux" => [tmpdir, Some("/tmp")]
    _ => []
  }
  for candidate in candidates {
    if non_empty_path(candidate) is Some(path) {
      return @mbpath.Path(path).normalize().to_string()
    }
  }
  raise MissingEnvironmentPath(name="temporary directory", platform~)
}

///|
fn app_data_dir_for_identifier(
  identifier : String,
) -> String raise AppPathError {
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
  @mbpath.Path(app_data_dir_for_identifier(identifier))
  .join("browser")
  .normalize()
  .to_string()
}

///|
fn app_log_dir(identifier : String) -> String raise AppPathError {
  let info = @native.runtime_info() catch {
    error => raise PlatformProbe(status=error.status(), detail=error.message())
  }
  app_log_dir_for_platform(
    info.platform,
    identifier,
    @env.get_env_var("HOME"),
    @env.get_env_var("LOCALAPPDATA"),
    @env.get_env_var("XDG_STATE_HOME"),
  )
}

///|
fn app_log_dir_for_platform(
  platform : String,
  identifier : String,
  home : String?,
  local_app_data : String?,
  xdg_state_home : String?,
) -> String raise AppPathError {
  validate_app_identifier(identifier)
  match platform {
    "macos" =>
      @mbpath.Path(require_path_base(home, platform))
      .join("Library/Logs")
      .join(identifier)
      .normalize()
      .to_string()
    "windows" =>
      @mbpath.Path(require_path_base(local_app_data, platform))
      .join(identifier)
      .join("Logs")
      .normalize()
      .to_string()
    "linux" => {
      let base = match non_empty_path(xdg_state_home) {
        Some(path) => @mbpath.Path(path)
        None =>
          @mbpath.Path(require_path_base(home, platform)).join(".local/state")
      }
      base.join(identifier).join("logs").normalize().to_string()
    }
    _ => raise MissingHomeDirectory(platform~)
  }
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

///|
fn require_environment_path(
  value : String?,
  name : String,
  platform : String,
) -> String raise AppPathError {
  match non_empty_path(value) {
    Some(path) => path
    None => raise MissingEnvironmentPath(name~, platform~)
  }
}
