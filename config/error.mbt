///|
/// Failures produced while loading and validating `moon.proton`.
pub(all) suberror ProjectConfigError {
  FileRead(path~ : String, detail~ : String)
  Syntax(name~ : String, diagnostics~ : String)
  InvalidRoot
  Validation(errors~ : Array[ProjectConfigError])
  MissingField(path~ : String)
  DuplicateField(path~ : String)
  DuplicateValue(path~ : String, value~ : String)
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
    Validation(errors~) => errors.map(fn(error) { error.message() }).join("\n")
    MissingField(path~) => "missing required field: " + path
    DuplicateField(path~) => render_field_key_error(path, true)
    DuplicateValue(path~, value~) => "duplicate value in " + path + ": " + value
    UnknownField(path~) => render_field_key_error(path, false)
    InvalidField(path~, expectation~) => path + " " + expectation
    UnsupportedField(path~, reason~) =>
      render_unsupported_field_error(path, reason)
    UnsupportedValue(path~, value~) => "unsupported " + path + ": " + value
  }
}

///|
fn render_unsupported_field_error(path : String, reason : String) -> String {
  let prefix = "moon.proton."
  if path.has_prefix(prefix) {
    "moon.proton field `" + path[prefix.length():].to_owned() + "` " + reason
  } else {
    path + " " + reason
  }
}

///|
fn render_field_key_error(path : String, duplicate : Bool) -> String {
  let prefix = "moon.proton."
  let verb = if duplicate { "Duplicate" } else { "Unexpected" }
  if path.has_prefix(prefix) {
    verb +
    " key '" +
    path[prefix.length():].to_owned() +
    "' found in moon.proton."
  } else {
    for scope in ["window", "entry", "frontend", "bundle"] {
      let scope_prefix = scope + "."
      if path.has_prefix(scope_prefix) {
        return verb +
          " key '" +
          path[scope_prefix.length():].to_owned() +
          "' found in moon.proton field `" +
          scope +
          "`."
      }
    }
    if duplicate {
      "duplicate field: " + path
    } else {
      "unknown field: " + path
    }
  }
}

///|
impl Show for ProjectConfigError with fn output(self, logger) {
  logger.write_string(self.message())
}
