///|
pub(all) suberror PowerMonitorError {
  BackendUnavailable(detail~ : String)
  OperationFailed(operation~ : String, detail~ : String)
} derive(Eq)

///|
pub extend PowerMonitorError with Eq::{not_equal, equal}

///|
pub extend PowerMonitorError with Show::{to_string, output}

///|
fn PowerMonitorError::message(self : PowerMonitorError) -> String {
  match self {
    BackendUnavailable(detail~) =>
      "power monitor backend is unavailable: " + detail
    OperationFailed(operation~, detail~) =>
      "power monitor operation failed (" + operation + "): " + detail
  }
}

///|
pub impl Show for PowerMonitorError with fn output(self, logger) {
  logger.write_string(self.message())
}
