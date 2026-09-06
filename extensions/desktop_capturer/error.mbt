///|
pub(all) suberror DesktopCapturerError {
  Unsupported(operation~ : String, detail~ : String)
  QueryFailed(detail~ : String)
} derive(Debug, Eq)

///|
pub fn DesktopCapturerError::message(self : DesktopCapturerError) -> String {
  match self {
    Unsupported(operation~, detail~) =>
      "desktop capturer operation is unsupported (" + operation + "): " + detail
    QueryFailed(detail~) => "desktop capturer query failed: " + detail
  }
}
