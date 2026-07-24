///|
/// Failures while managing the process keep-awake guard.
suberror KeepAwakeError {
  UnknownScope(scope~ : String)
  AlreadyActive
  AcquireFailed(detail~ : String)
  ReleaseFailed(detail~ : String)
} derive(Debug, Eq)

///|
fn KeepAwakeError::message(self : KeepAwakeError) -> String {
  match self {
    UnknownScope(scope~) => "unknown keepAwake scope: " + scope
    AlreadyActive => "keepAwake guard is already active"
    AcquireFailed(detail~) => "failed to acquire keepAwake guard: " + detail
    ReleaseFailed(detail~) => "failed to release keepAwake guard: " + detail
  }
}

///|
impl Show for KeepAwakeError with fn output(self, logger) {
  logger.write_string(self.message())
}
