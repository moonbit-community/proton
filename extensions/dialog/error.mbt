///|
/// Failures while creating or waiting for a native dialog.
suberror DialogError {
  BeginFailed(kind~ : String, error~ : @native.NativeError)
  PollFailed(kind~ : String, error~ : @native.NativeError)
} derive(Debug, Eq)

///|
fn DialogError::message(self : DialogError) -> String {
  match self {
    BeginFailed(kind~, error~) =>
      "failed to open " + kind + " dialog: " + error.message()
    PollFailed(kind~, error~) =>
      "failed to poll " + kind + " dialog: " + error.message()
  }
}

///|
impl Show for DialogError with fn output(self, logger) {
  logger.write_string(self.message())
}
