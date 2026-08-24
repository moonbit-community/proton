///|
/// Failures while querying screen and display state.
suberror ScreenMonitorError {
  BackendUnavailable(detail~ : String)
  QueryFailed(operation~ : String, detail~ : String)
} derive(Debug, Eq)

///|
pub extend ScreenMonitorError with Eq::{not_equal, equal}

///|
pub extend ScreenMonitorError with Debug::{to_repr}

///|
pub extend ScreenMonitorError with Show::{to_string, output}

///|
fn ScreenMonitorError::message(self : ScreenMonitorError) -> String {
  match self {
    BackendUnavailable(detail~) =>
      "screen monitor backend is unavailable: " + detail
    QueryFailed(operation~, detail~) =>
      "screen monitor query failed (" + operation + "): " + detail
  }
}

///|
impl Show for ScreenMonitorError with fn output(self, logger) {
  logger.write_string(self.message())
}
