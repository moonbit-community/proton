///|
/// Failures while decoding or validating Proton IPC protocol values.
pub(all) suberror IpcError {
  MalformedJson(detail~ : String)
  InvalidPayload(kind~ : String, detail~ : String)
  UnsupportedVersion(scope~ : String, actual~ : Int, supported~ : Int)
  UnsupportedFrameKind(kind~ : String)
  UnexpectedFrameKind(expected~ : String, actual~ : String)
  EmptyField(path~ : String)
  InvalidErrorResponseBody
} derive(Debug, Eq)

///|
pub fn IpcError::message(self : IpcError) -> String {
  match self {
    MalformedJson(detail~) => "Invalid IPC JSON: " + detail
    InvalidPayload(kind~, detail~) =>
      "Invalid IPC " + kind + " payload: " + detail
    UnsupportedVersion(scope~, actual~, supported~) =>
      "Unsupported IPC " +
      scope +
      " version: " +
      actual.to_string() +
      " (supported: " +
      supported.to_string() +
      ")"
    UnsupportedFrameKind(kind~) => "Unsupported IPC frame kind: " + kind
    UnexpectedFrameKind(expected~, actual~) =>
      "IPC frame kind is not " + expected + ": " + actual
    EmptyField(path~) => path + " must not be empty"
    InvalidErrorResponseBody => "IPC error response body must be a string"
  }
}

///|
impl Show for IpcError with fn output(self, logger) {
  logger.write_string(self.message())
}
