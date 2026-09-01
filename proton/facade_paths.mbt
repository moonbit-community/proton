///|
/// Failures while resolving framework-owned application paths.
pub(all) suberror AppPathError {
  MissingApplicationIdentifier
  InvalidIdentifier(identifier~ : String)
  MissingHomeDirectory(platform~ : String)
  MissingEnvironmentPath(name~ : String, platform~ : String)
  MissingExecutablePath
  UnsupportedPath(kind~ : String, platform~ : String)
  InvalidPathOverride(kind~ : String, path~ : String, reason~ : String)
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
    InvalidPathOverride(kind~, path~, reason~) =>
      "cannot override application path " +
      kind +
      " with " +
      path +
      ": " +
      reason
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
fn AppPathKind::electron_name(self : AppPathKind) -> String {
  match self {
    Home => "home"
    AppData => "appData"
    UserData => "userData"
    SessionData => "sessionData"
    Temp => "temp"
    Executable => "exe"
    Logs => "logs"
    Assets => "assets"
    Module => "module"
    Desktop => "desktop"
    Documents => "documents"
    Downloads => "downloads"
    Music => "music"
    Pictures => "pictures"
    Videos => "videos"
    Recent => "recent"
  }
}

///|
fn AppPathKind::expects_directory(self : AppPathKind) -> Bool {
  match self {
    Executable | Module => false
    _ => true
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
  self.path(AppPathKind::UserData)
}

///|
/// Overrides a standard application path before the application runtime starts.
///
/// The path must be absolute and already exist, matching Electron's `setPath`
/// validation. Runtime-owned paths such as `SessionData` and `Logs` are
/// consumed by Proton startup in addition to being returned by `App::path`.
pub fn App::set_path(
  self : App,
  kind : AppPathKind,
  path : String,
) -> App raise AppPathError {
  let platform = runtime_platform()
  ensure_path_available(kind, platform)
  let normalized = normalize_path_override(kind, path, true)
  self.path_overrides[kind.electron_name()] = normalized
  if kind == AppPathKind::Logs {
    self.electron_default_logs_path = false
    self.create_logs_path = false
  }
  self
}

///|
/// Selects the application log directory before runtime startup.
///
/// A custom absolute path is created when the application starts. Omitting the
/// path selects Electron's default: the platform log directory on macOS and a
/// `logs` directory inside `UserData` on Windows and Linux.
pub fn App::set_app_logs_path(
  self : App,
  path? : String,
) -> App raise AppPathError {
  match path {
    Some(path) => {
      self.path_overrides[AppPathKind::Logs.electron_name()] = normalize_path_override(
        AppPathKind::Logs,
        path,
        false,
      )
      self.electron_default_logs_path = false
    }
    None => self.electron_default_logs_path = true
  }
  self.create_logs_path = true
  self
}

///|
/// Resolves a standard application path.
///
/// `UserData`, `SessionData`, and `Logs` use the application's stable
/// reverse-DNS identifier instead of its display name so package renames do not
/// move persisted state.
pub fn App::path(self : App, kind : AppPathKind) -> String raise AppPathError {
  let platform = runtime_platform()
  ensure_path_available(kind, platform)
  if kind == AppPathKind::Logs && self.electron_default_logs_path {
    return self.electron_default_log_dir(platform)
  }
  match self.path_overrides.get(kind.electron_name()) {
    Some(path) => return path
    None => ()
  }
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
    SessionData => self.session_data_path(self.application_identifier())
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
    Assets => executable_dir()
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
    Recent => resolve_system_path(@native.SystemPathKind::Recent, "recent")
  }
}

///|
fn App::session_data_path(
  self : App,
  identifier : String,
) -> String raise AppPathError {
  match self.path_overrides.get(AppPathKind::SessionData.electron_name()) {
    Some(path) => path
    None => {
      let user_data = match
        self.path_overrides.get(AppPathKind::UserData.electron_name()) {
        Some(path) => path
        None =>
          app_data_dir_for_platform(
            runtime_platform(),
            identifier,
            @env.get_env_var("HOME"),
            @env.get_env_var("LOCALAPPDATA"),
            @env.get_env_var("XDG_DATA_HOME"),
          )
      }
      @mbpath.Path(user_data).join("browser").normalize().to_string()
    }
  }
}

///|
fn runtime_platform() -> String raise AppPathError {
  let info = @native.runtime_info() catch {
    error => raise PlatformProbe(status=error.status(), detail=error.message())
  }
  info.platform
}

///|
fn ensure_path_available(
  kind : AppPathKind,
  platform : String,
) -> Unit raise AppPathError {
  match kind {
    Assets if platform != "windows" && platform != "linux" =>
      raise UnsupportedPath(kind="assets", platform~)
    Recent if platform != "windows" =>
      raise UnsupportedPath(kind="recent", platform~)
    _ => ()
  }
}

///|
fn normalize_path_override(
  kind : AppPathKind,
  path : String,
  must_exist : Bool,
) -> String raise AppPathError {
  let path = path.trim().to_owned()
  guard path != "" else {
    raise InvalidPathOverride(
      kind=kind.electron_name(),
      path~,
      reason="path must not be empty",
    )
  }
  let candidate : @mbpath.Path = path
  guard candidate.is_absolute() else {
    raise InvalidPathOverride(
      kind=kind.electron_name(),
      path~,
      reason="path must be absolute",
    )
  }
  let normalized = candidate.normalize().to_string()
  let exists = @mbfs.path_exists(normalized)
  if must_exist && !exists {
    raise InvalidPathOverride(
      kind=kind.electron_name(),
      path=normalized,
      reason="path does not exist",
    )
  }
  if exists && kind.expects_directory() && !path_is_directory(normalized) {
    raise InvalidPathOverride(
      kind=kind.electron_name(),
      path=normalized,
      reason="path is not a directory",
    )
  }
  if exists && !kind.expects_directory() && !path_is_file(normalized) {
    raise InvalidPathOverride(
      kind=kind.electron_name(),
      path=normalized,
      reason="path is not a file",
    )
  }
  normalized
}

///|
fn path_is_directory(path : String) -> Bool {
  @mbfs.is_dir(path) catch {
    _ => false
  }
}

///|
fn path_is_file(path : String) -> Bool {
  @mbfs.is_file(path) catch {
    _ => false
  }
}

///|
fn App::electron_default_log_dir(
  self : App,
  platform : String,
) -> String raise AppPathError {
  if platform == "macos" {
    app_log_dir_for_platform(
      platform,
      self.application_identifier(),
      @env.get_env_var("HOME"),
      @env.get_env_var("LOCALAPPDATA"),
      @env.get_env_var("XDG_STATE_HOME"),
    )
  } else {
    @mbpath.Path(self.path(AppPathKind::UserData))
    .join("logs")
    .normalize()
    .to_string()
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
