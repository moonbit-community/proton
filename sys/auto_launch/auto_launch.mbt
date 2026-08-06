///|
/// Normalizes constructor inputs and supports dependency injection in tests.
fn require_supported_platform(
  platform : Platform,
) -> Result[Unit, AutoLaunchError] {
  if backend_for_platform(platform) == BackendKind::UnsupportedBackend {
    Err(AutoLaunchError::UnsupportedPlatform(platform))
  } else {
    Ok(())
  }
}

///|
/// Trims caller input and rejects empty values with a typed validation error.
fn require_non_empty_text(
  text : String,
  empty_error : AutoLaunchError,
) -> Result[String, AutoLaunchError] {
  let trimmed = trim_text(text)
  if trimmed.is_empty() {
    Err(empty_error)
  } else {
    Ok(trimmed)
  }
}

///|
/// Resolves the executable path from explicit input or the runtime probe.
fn resolve_executable_path(
  path : String?,
  get_current_executable_path~ : () -> Result[String, AutoLaunchError],
) -> Result[String, AutoLaunchError] {
  match path {
    Some(explicit_path) =>
      require_non_empty_text(
        explicit_path,
        AutoLaunchError::EmptyExecutablePath,
      )
    None => get_current_executable_path()
  }
}

///|
/// Normalizes constructor inputs and supports dependency injection in tests.
fn new_with(
  platform : Platform,
  name : String,
  path : String?,
  launch_in_background : Bool,
  background_arg : String,
  extra_arguments : Array[String],
  identifier : String?,
  get_current_executable_path~ : () -> Result[String, AutoLaunchError],
) -> Result[AutoLaunch, AutoLaunchError] {
  match require_supported_platform(platform) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }

  let trimmed_name = match
    require_non_empty_text(name, AutoLaunchError::EmptyName) {
    Ok(value) => value
    Err(error) => return Err(error)
  }

  let trimmed_background_arg = trim_text(background_arg)
  if launch_in_background && trimmed_background_arg.is_empty() {
    return Err(AutoLaunchError::EmptyBackgroundArgument)
  }

  let resolved_path = match
    resolve_executable_path(path, get_current_executable_path~) {
    Ok(value) => value
    Err(error) => return Err(error)
  }

  if !is_absolute_path(platform, resolved_path) {
    return Err(AutoLaunchError::RelativeExecutablePath(resolved_path))
  }

  Ok(AutoLaunch::{
    config: {
      name: trimmed_name,
      app_path: resolved_path,
      identifier: default_identifier(trimmed_name, identifier),
      launch_in_background,
      background_arg: trimmed_background_arg,
      extra_arguments,
    },
  })
}

///|
/// Create an auto-launch configuration for the current platform.
///
/// `name` is the human-readable application name shown in generated desktop
/// entries. `path` defaults to the current executable path when omitted.
///
/// When `launch_in_background` is `true`, the package appends
/// `background_arg` before any `extra_arguments`. This mirrors the common
/// `--hidden` startup convention used by desktop applications.
///
/// `identifier` controls the stable registry value or file name used by the
/// backend. When omitted, it is derived from `name`.
///
/// Returns `Err(AutoLaunchError)` when validation fails, when the current
/// platform is unsupported, or when the executable path cannot be discovered.
///
/// The resulting value is reusable: you can keep it around and call
/// `enable()`, `disable()`, and `is_enabled()` multiple times.
///
/// # Example
/// ```mbt nocheck
/// let launcher = @proton_auto_launch.new(
///   "MoonBit Demo",
///   path="/usr/bin/moonbit",
///   launch_in_background=true,
///   extra_arguments=["--serve"],
/// )
/// ```
pub fn new(
  name : String,
  path? : String,
  launch_in_background? : Bool = false,
  background_arg? : String = "--hidden",
  extra_arguments? : Array[String] = [],
  identifier? : String,
) -> Result[AutoLaunch, AutoLaunchError] {
  new_with(
    current_platform(),
    name,
    path,
    launch_in_background,
    background_arg,
    extra_arguments,
    identifier,
    get_current_executable_path=current_executable_path_result,
  )
}

///|
/// Returns the configured human-readable application name.
///
/// This is the display name used in generated desktop-entry style metadata. It
/// may contain spaces and punctuation and is independent from the backend
/// identifier used for file names or registry keys.
pub fn AutoLaunch::name(self : AutoLaunch) -> String {
  self.config.name
}

///|
/// Returns the resolved absolute executable path that will be launched.
///
/// The value returned here is always the normalized absolute path that passed
/// constructor validation, either from the explicit `path` argument or from the
/// current executable path discovered by the native backend.
pub fn AutoLaunch::path(self : AutoLaunch) -> String {
  self.config.app_path
}

///|
/// Returns the stable backend identifier used for the registry value or file
/// name.
///
/// This value is derived from `name` unless the caller provided `identifier`
/// explicitly. It is sanitized for backend-safe usage and is what ties
/// `enable()`, `disable()`, and `is_enabled()` to the same platform entry.
pub fn AutoLaunch::identifier(self : AutoLaunch) -> String {
  self.config.identifier
}

///|
/// Enable auto-launch for this configuration on the current platform.
///
/// On supported platforms this creates or updates the corresponding startup
/// entry:
///
/// - Windows: writes the current-user `Run` registry value
/// - macOS: writes a LaunchAgent plist under `~/Library/LaunchAgents`
/// - Linux: writes an XDG autostart desktop entry under
///   `~/.config/autostart`
///
/// Returns `Ok(())` when the entry was written successfully.
pub fn AutoLaunch::enable(self : AutoLaunch) -> Result[Unit, AutoLaunchError] {
  enable_with(
    self,
    current_platform(),
    home_directory_result,
    windows_set_run_entry_result,
    write_text_file_result,
  )
}

///|
/// Disable auto-launch for this configuration on the current platform.
///
/// Missing entries are treated as already-disabled and therefore do not produce
/// an error in the native backend.
pub fn AutoLaunch::disable(self : AutoLaunch) -> Result[Unit, AutoLaunchError] {
  disable_with(
    self,
    current_platform(),
    home_directory_result,
    windows_delete_run_entry_result,
    remove_file_result,
  )
}

///|
/// Check whether the auto-launch entry currently exists for this configuration.
///
/// This is an existence check against the backend entry identified by
/// `identifier()`. It does not attempt to prove that the entry still contains
/// the exact expected command line beyond the backend's own lookup semantics.
pub fn AutoLaunch::is_enabled(
  self : AutoLaunch,
) -> Result[Bool, AutoLaunchError] {
  is_enabled_with(
    self,
    current_platform(),
    home_directory_result,
    windows_run_entry_exists_result,
    file_exists_result,
  )
}
