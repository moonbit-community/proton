///|
/// Failures while making HTTP requests through the extension layer.
suberror NetError {
  RequestFailed(detail~ : String)
  InvalidUrl(detail~ : String)
  UnsupportedMethod(name~ : String)
} derive(Debug, Eq)

///|
pub extend NetError with Eq::{not_equal, equal}

///|
pub extend NetError with Debug::{to_repr}

///|
pub extend NetError with Show::{to_string, output}

///|
fn NetError::message(self : NetError) -> String {
  match self {
    RequestFailed(detail~) => "HTTP request failed: " + detail
    InvalidUrl(detail~) => "invalid URL: " + detail
    UnsupportedMethod(name~) => "unsupported HTTP method: " + name
  }
}

///|
impl Show for NetError with fn output(self, logger) {
  logger.write_string(self.message())
}
