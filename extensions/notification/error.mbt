///|
/// Failures while validating or delivering native notifications.
suberror NotificationError {
  EmptyBody
  UnsupportedPlatform
  NativeOperation(detail~ : String)
} derive(Debug, Eq)

///|
pub extend NotificationError with Eq::{not_equal, equal}

///|
pub extend NotificationError with Debug::{to_repr}

///|
pub extend NotificationError with Show::{to_string, output}

///|
fn NotificationError::message(self : NotificationError) -> String {
  match self {
    EmptyBody => "notification body must not be empty"
    UnsupportedPlatform =>
      "native notifications are not implemented on this platform"
    NativeOperation(detail~) =>
      "native notification operation failed: " + detail
  }
}

///|
impl Show for NotificationError with fn output(self, logger) {
  logger.write_string(self.message())
}
