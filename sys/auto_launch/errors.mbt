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
/// This enum derives `Eq` and implements `Show`, which makes it convenient to
/// inspect in tests and to print in user-facing diagnostics.
pub enum AutoLaunchError {
  EmptyName
  EmptyExecutablePath
  EmptyBackgroundArgument
  ExecutablePathUnavailable
  HomeDirectoryUnavailable
  RelativeExecutablePath(String)
  UnsupportedPlatform(Platform)
  NativeFailure(action~ : String, message~ : String)
} derive(Debug, Eq)

///|
pub impl Show for AutoLaunchError with fn output(self : AutoLaunchError, logger) {
  match self {
    EmptyName => logger.write_string("EmptyName")
    EmptyExecutablePath => logger.write_string("EmptyExecutablePath")
    EmptyBackgroundArgument => logger.write_string("EmptyBackgroundArgument")
    ExecutablePathUnavailable =>
      logger.write_string("ExecutablePathUnavailable")
    HomeDirectoryUnavailable => logger.write_string("HomeDirectoryUnavailable")
    RelativeExecutablePath(path) => {
      logger.write_string("RelativeExecutablePath(")
      logger.write_object(path)
      logger.write_string(")")
    }
    UnsupportedPlatform(platform) => {
      logger.write_string("UnsupportedPlatform(")
      logger.write_object(platform)
      logger.write_string(")")
    }
    NativeFailure(action~, message~) => {
      logger.write_string("NativeFailure(action=")
      logger.write_object(action)
      logger.write_string(", message=")
      logger.write_object(message)
      logger.write_string(")")
    }
  }
}
