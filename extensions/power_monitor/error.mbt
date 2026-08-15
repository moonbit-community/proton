///|
/// Failures while querying system power and idle state.
suberror PowerMonitorError {
  BackendUnavailable(detail~ : String)
  QueryFailed(operation~ : String, detail~ : String)
} derive(Debug, Eq)

///|
pub extend PowerMonitorError with Eq::{not_equal, equal}

///|
pub extend PowerMonitorError with Debug::{to_repr}

///|
pub extend PowerMonitorError with Show::{to_string, output}

///|
fn PowerMonitorError::message(self : PowerMonitorError) -> String {
  match self {
    BackendUnavailable(detail~) =>
      "power monitor backend is unavailable: " + detail
    QueryFailed(operation~, detail~) =>
      "power monitor query failed (" + operation + "): " + detail
  }
}

///|
impl Show for PowerMonitorError with fn output(self, logger) {
  logger.write_string(self.message())
}
