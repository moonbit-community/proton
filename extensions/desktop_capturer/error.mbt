///|
pub(all) suberror DesktopCapturerError {
  Unsupported(operation~ : String, detail~ : String)
  QueryFailed(detail~ : String)
} derive(Debug, Eq)

///|
pub extend DesktopCapturerError with Debug::{to_repr}

///|
pub extend DesktopCapturerError with Eq::{not_equal, equal}

///|
pub fn DesktopCapturerError::message(self : DesktopCapturerError) -> String {
  match self {
    Unsupported(operation~, detail~) =>
      "desktop capturer operation is unsupported (" + operation + "): " + detail
    QueryFailed(detail~) => "desktop capturer query failed: " + detail
  }
}
