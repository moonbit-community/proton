///|
/// Errors returned by `auto_launch` operations.
///
/// The error model is intentionally small and stable:
///
/// - validation errors describe incorrect input supplied by the caller
/// - discovery errors describe missing runtime information such as the current
///   executable path or home directory
/// - `NativeFailure` reports a backend-specific failure message produced by the
///   underlying platform API
///
/// This enum derives `Eq` and `Show`, which makes it convenient to inspect in
/// tests and to print in user-facing diagnostics.
pub enum AutoLaunchError {
  EmptyName
  EmptyExecutablePath
  EmptyBackgroundArgument
  ExecutablePathUnavailable
  HomeDirectoryUnavailable
  RelativeExecutablePath(String)
  UnsupportedPlatform(Platform)
  NativeFailure(action~ : String, message~ : String)
} derive(Debug, Eq, Show)
