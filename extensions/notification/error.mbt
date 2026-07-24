///|
/// Failures while validating or delivering native notifications.
suberror NotificationError {
  EmptyBody
  NativeCapability(error~ : @proton_native.NativeError)
  UnsupportedPlatform
  NativeShow(error~ : @proton_native.NativeError)
  NativePoll(error~ : @proton_native.NativeError)
  NativeCleanup(error~ : @proton_native.NativeError)
} derive(Debug, Eq)

///|
fn NotificationError::message(self : NotificationError) -> String {
  match self {
    EmptyBody => "notification body must not be empty"
    NativeCapability(error~) =>
      "failed to query native notification support: " + error.message()
    UnsupportedPlatform =>
      "native notifications are not implemented on this platform"
    NativeShow(error~) =>
      "failed to show native notification: " + error.message()
    NativePoll(error~) =>
      "failed to poll native notification clicks: " + error.message()
    NativeCleanup(error~) =>
      "failed to clean up native notifications: " + error.message()
  }
}

///|
impl Show for NotificationError with fn output(self, logger) {
  logger.write_string(self.message())
}
