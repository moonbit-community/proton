///|
/// Desktop platform reported by the native tray backend.
///
/// `Windows`, `Linux`, and `Macos` identify a backend this package knows how to
/// drive. `Unknown` is returned when the native stub cannot map the host
/// operating system to a supported variant, which typically also means tray
/// creation will fail. Use this to branch platform-specific setup or to enrich
/// diagnostics; the value is derived from `current_platform()`.
pub enum Platform {
  Windows
  Linux
  Macos
  Unknown
} derive(Debug, Eq, ToJson)

///|
pub extend Platform with Eq::{not_equal, equal}

///|
pub extend Platform with Debug::{to_repr}

///|
pub extend Platform with ToJson::{to_json}

///|
pub extend Platform with Show::{to_string, output}

///|
/// Renders a `Platform` as its capitalized backend name.
pub impl Show for Platform with fn output(self, logger) {
  logger.write_string(
    match self {
      Windows => "Windows"
      Linux => "Linux"
      Macos => "Macos"
      Unknown => "Unknown"
    },
  )
}

///|
/// Returns the desktop platform detected by the native backend for the current
/// process.
///
/// The value is computed by the native stub so it matches the operating system
/// that actually builds and runs the package.
///
/// Use this to branch platform-specific setup code around tray creation or to
/// surface clearer diagnostics in logs and error messages. When the backend
/// cannot map the host operating system to a known variant, this returns
/// `Unknown`.
pub fn current_platform() -> Platform {
  platform_from_tag(current_platform_ffi())
}

///|
/// Returns the default identifier used by `create()` when callers do not
/// provide one.
///
/// The identifier is used as the native tray instance id on platforms that
/// require one, and keeping it stable makes logs and diagnostics easier to
/// follow.
///
/// Applications with a single tray icon can usually rely on this value as-is.
/// Multi-tray applications may still prefer to provide their own stable,
/// application-specific identifiers so native backends can distinguish
/// instances consistently across runs.
pub fn default_identifier() -> String {
  "moonbit-tray"
}

///|
/// Maps the native platform tag to the public `Platform` enum.
fn platform_from_tag(tag : Int) -> Platform {
  match tag {
    1 => Windows
    2 => Linux
    3 => Macos
    _ => Unknown
  }
}

///|
/// Decodes the support-probe failure message or falls back to a generic error.
fn support_error_message() -> String {
  decode_bytes(support_error_ffi()).unwrap_or(
    "tray is not supported on this platform",
  )
}

///|
/// Trims user input and replaces an empty identifier with the default value.
fn normalize_identifier(identifier : String) -> String {
  let trimmed = identifier.trim().to_owned()
  if trimmed.is_empty() {
    default_identifier()
  } else {
    trimmed
  }
}
