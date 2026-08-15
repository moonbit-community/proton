///|
/// Enumerates the operating systems that this package can detect at runtime.
///
/// The value is derived from the active native backend rather than from
/// build-time configuration alone, so it reflects the platform that the
/// current executable is actually running on.
pub enum Platform {
  Windows
  Macos
  Linux
  Unsupported
} derive(Debug, Eq)

///|
pub extend Platform with Eq::{not_equal, equal}

///|
pub extend Platform with Debug::{to_repr}

///|
pub extend Platform with Show::{to_string, output}

///|
pub impl Show for Platform with fn output(self : Platform, logger) {
  logger.write_string(
    match self {
      Windows => "Windows"
      Macos => "Macos"
      Linux => "Linux"
      Unsupported => "Unsupported"
    },
  )
}

///|
/// Internal backend categories for supported startup mechanisms.
enum BackendKind {
  WindowsRegistry
  MacLaunchAgent
  LinuxDesktopEntry
  UnsupportedBackend
} derive(Debug, Eq)

///|
pub extend BackendKind with Eq::{not_equal, equal}

///|
pub extend BackendKind with Debug::{to_repr}

///|
/// Decodes the numeric platform code returned by the native layer.
fn platform_from_code(code : Int) -> Platform {
  match code {
    1 => Platform::Windows
    2 => Platform::Macos
    3 => Platform::Linux
    _ => Platform::Unsupported
  }
}

///|
/// Returns the auto-launch backend used for `platform`.
fn backend_for_platform(platform : Platform) -> BackendKind {
  match platform {
    Platform::Windows => BackendKind::WindowsRegistry
    Platform::Macos => BackendKind::MacLaunchAgent
    Platform::Linux => BackendKind::LinuxDesktopEntry
    Platform::Unsupported => BackendKind::UnsupportedBackend
  }
}

///|
/// Detects the current runtime platform for the active native build.
///
/// This function is a lightweight probe over the native FFI layer. It is safe
/// to call repeatedly and is primarily useful for platform-specific setup,
/// conditional logging, or selecting example paths in applications and tests.
pub fn current_platform() -> Platform {
  platform_from_code(platform_code_ffi())
}

///|
/// Returns `true` when the current runtime platform has a supported auto-launch
/// backend in this package.
///
/// Supported platforms currently map to these backends:
///
/// - `Windows`: current-user `Run` registry value
/// - `Macos`: per-user LaunchAgent plist
/// - `Linux`: XDG autostart desktop entry
///
/// `Unsupported` means the package was compiled or executed in an environment
/// for which no native backend is implemented.
pub fn is_supported() -> Bool {
  backend_for_platform(current_platform()) != BackendKind::UnsupportedBackend
}
