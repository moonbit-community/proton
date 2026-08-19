///|
pub(all) suberror ScreenMonitorError {
  BackendUnavailable(detail~ : String)
  OperationFailed(operation~ : String, detail~ : String)
  Empty
} derive(Eq)

///|
pub extend ScreenMonitorError with Eq::{not_equal, equal}

///|
pub extend ScreenMonitorError with Show::{to_string, output}

///|
fn ScreenMonitorError::message(self : ScreenMonitorError) -> String {
  match self {
    BackendUnavailable(detail~) =>
      "screen monitor backend is unavailable: " + detail
    OperationFailed(operation~, detail~) =>
      "screen monitor operation failed (" + operation + "): " + detail
    Empty => "no display is available"
  }
}

///|
pub impl Show for ScreenMonitorError with fn output(self, logger) {
  logger.write_string(self.message())
}
