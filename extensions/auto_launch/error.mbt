///|
/// Failures while resolving or mutating an operating-system startup entry.
suberror AutoLaunchError {
  InvalidConfiguration(detail~ : String)
  QueryFailed(identifier~ : String, detail~ : String)
  EnableFailed(identifier~ : String, detail~ : String)
  DisableFailed(identifier~ : String, detail~ : String)
} derive(Debug, Eq)

///|
fn AutoLaunchError::message(self : AutoLaunchError) -> String {
  match self {
    InvalidConfiguration(detail~) =>
      "invalid auto-launch configuration: " + detail
    QueryFailed(identifier~, detail~) =>
      "failed to query auto-launch entry " + identifier + ": " + detail
    EnableFailed(identifier~, detail~) =>
      "failed to enable auto-launch entry " + identifier + ": " + detail
    DisableFailed(identifier~, detail~) =>
      "failed to disable auto-launch entry " + identifier + ": " + detail
  }
}

///|
impl Show for AutoLaunchError with fn output(self, logger) {
  logger.write_string(self.message())
}
