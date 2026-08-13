///|
/// Failures while managing child processes through the extension layer.
suberror ProcessExtensionError {
  SpawnFailed(detail~ : String)
  WaitFailed(detail~ : String)
  KillFailed(detail~ : String)
  UnknownProcess(process_id~ : Int)
} derive(Debug, Eq)

///|
fn ProcessExtensionError::message(self : ProcessExtensionError) -> String {
  match self {
    SpawnFailed(detail~) => "failed to spawn process: " + detail
    WaitFailed(detail~) => "failed to wait for process: " + detail
    KillFailed(detail~) => "failed to kill process: " + detail
    UnknownProcess(process_id~) =>
      "unknown process id: " + process_id.to_string()
  }
}

///|
impl Show for ProcessExtensionError with fn output(self, logger) {
  logger.write_string(self.message())
}
