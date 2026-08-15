///|
/// An update manifest could not be decoded.
///
/// Every variant names the field at fault, because a manifest is written by a
/// release process and read by a client that cannot ask for a correction.
pub(all) suberror ManifestError {
  NotJson
  NotAnObject(path~ : String)
  UnknownSchemaVersion(found~ : Int)
  UnknownField(path~ : String)
  MissingField(path~ : String)
  InvalidField(path~ : String, expectation~ : String)
} derive(Debug, Eq)

///|
pub extend ManifestError with Eq::{not_equal, equal}

///|
pub extend ManifestError with Debug::{to_repr}

///|
pub extend ManifestError with Show::{to_string, output}

///|
pub fn ManifestError::message(self : ManifestError) -> String {
  match self {
    NotJson => "manifest is not valid JSON"
    NotAnObject(path~) => "\{path} must be an object"
    UnknownSchemaVersion(found~) =>
      "unsupported manifest schema_version: \{found}"
    UnknownField(path~) => "unknown manifest field: \{path}"
    MissingField(path~) => "missing manifest field: \{path}"
    InvalidField(path~, expectation~) => "\{path} \{expectation}"
  }
}

///|
impl Show for ManifestError with fn output(self, logger) {
  logger.write_string(self.message())
}
