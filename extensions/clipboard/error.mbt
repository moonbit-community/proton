///|
/// Failures while accessing the system clipboard.
suberror ClipboardError {
  Unsupported(detail~ : String)
  ReadFailed(detail~ : String)
  WriteFailed(detail~ : String)
} derive(Debug, Eq)

///|
fn ClipboardError::message(self : ClipboardError) -> String {
  match self {
    Unsupported(detail~) => "clipboard is unavailable: " + detail
    ReadFailed(detail~) => "failed to read clipboard text: " + detail
    WriteFailed(detail~) => "failed to write clipboard text: " + detail
  }
}

///|
impl Show for ClipboardError with fn output(self, logger) {
  logger.write_string(self.message())
}
