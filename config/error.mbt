///|
/// Failures produced while loading and validating `moon.proton`.
pub(all) suberror ProjectConfigError {
  FileRead(path~ : String, detail~ : String)
  Syntax(name~ : String, diagnostics~ : String)
  InvalidRoot
  MissingField(path~ : String)
  DuplicateField(path~ : String)
  UnknownField(path~ : String)
  InvalidField(path~ : String, expectation~ : String)
  UnsupportedField(path~ : String, reason~ : String)
  UnsupportedValue(path~ : String, value~ : String)
} derive(Debug, Eq)

///|
pub fn ProjectConfigError::message(self : ProjectConfigError) -> String {
  match self {
    FileRead(path~, detail~) => "failed to read " + path + ": " + detail
    Syntax(diagnostics~, ..) => diagnostics
    InvalidRoot => "moon.proton root must be a field list"
    MissingField(path~) => "missing required field: " + path
    DuplicateField(path~) => "duplicate field: " + path
    UnknownField(path~) => "unknown field: " + path
    InvalidField(path~, expectation~) => path + " " + expectation
    UnsupportedField(path~, reason~) => path + " is not supported: " + reason
    UnsupportedValue(path~, value~) => "unsupported " + path + ": " + value
  }
}

///|
impl Show for ProjectConfigError with fn output(self, logger) {
  logger.write_string(self.message())
}
