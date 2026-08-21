///|
/// Failures while creating or waiting for a native dialog.
suberror DialogError {
  WindowUnavailable
  OperationFailed(kind~ : String, detail~ : String)
} derive(Debug, Eq)

///|
pub extend DialogError with Eq::{not_equal, equal}

///|
pub extend DialogError with Debug::{to_repr}

///|
pub extend DialogError with Show::{to_string, output}

///|
fn DialogError::message(self : DialogError) -> String {
  match self {
    WindowUnavailable => "dialog command has no issuing window"
    OperationFailed(kind~, detail~) =>
      "failed to show " + kind + " dialog: " + detail
  }
}

///|
impl Show for DialogError with fn output(self, logger) {
  logger.write_string(self.message())
}
