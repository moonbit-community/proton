///|
/// Failures while spawning or managing a child process.
pub(all) suberror ProcessError {
  SpawnFailed(detail~ : String)
  WaitFailed(detail~ : String)
  KillFailed(detail~ : String)
} derive(Eq)

///|
pub extend ProcessError with Eq::{not_equal, equal}

///|
pub extend ProcessError with Show::{to_string, output}

///|
fn ProcessError::message(self : ProcessError) -> String {
  match self {
    SpawnFailed(detail~) => "failed to spawn process: " + detail
    WaitFailed(detail~) => "failed to wait for process: " + detail
    KillFailed(detail~) => "failed to kill process: " + detail
  }
}

///|
pub impl Show for ProcessError with fn output(self, logger) {
  logger.write_string(self.message())
}
