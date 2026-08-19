///|
/// Failures produced while loading and validating `proton.project.json`.
pub(all) suberror ProjectConfigError {
  FileRead(path~ : String, detail~ : String)
  Syntax(name~ : String, diagnostics~ : String)
  InvalidRoot
  Validation(errors~ : Array[ProjectConfigError])
  MissingField(path~ : String)
  DuplicateValue(path~ : String, value~ : String)
  UnknownField(path~ : String)
  InvalidField(path~ : String, expectation~ : String)
  UnsupportedField(path~ : String, reason~ : String)
  UnsupportedValue(path~ : String, value~ : String)
} derive(Debug, Eq)

///|
pub extend ProjectConfigError with Eq::{not_equal, equal}

///|
pub extend ProjectConfigError with Debug::{to_repr}

///|
pub extend ProjectConfigError with Show::{to_string, output}

///|
pub fn ProjectConfigError::message(self : ProjectConfigError) -> String {
  match self {
    FileRead(path~, detail~) => "failed to read " + path + ": " + detail
    Syntax(name~, diagnostics~) => name + ": " + diagnostics
    InvalidRoot => "proton.project.json root must be a JSON object"
    Validation(errors~) => errors.map(fn(error) { error.message() }).join("\n")
    MissingField(path~) => "missing required field: " + path
    DuplicateValue(path~, value~) => "duplicate value in " + path + ": " + value
    UnknownField(path~) => render_field_key_error(path)
    InvalidField(path~, expectation~) => path + " " + expectation
    UnsupportedField(path~, reason~) =>
      render_unsupported_field_error(path, reason)
    UnsupportedValue(path~, value~) => "unsupported " + path + ": " + value
  }
}

///|
fn render_unsupported_field_error(path : String, reason : String) -> String {
  let prefix = "proton.project.json."
  if path.has_prefix(prefix) {
    "proton.project.json field `" +
    path[prefix.length():].to_owned() +
    "` " +
    reason
  } else {
    path + " " + reason
  }
}

///|
fn render_field_key_error(path : String) -> String {
  let prefix = "proton.project.json."
  if path.has_prefix(prefix) {
    "Unexpected" +
    " key '" +
    path[prefix.length():].to_owned() +
    "' found in proton.project.json."
  } else {
    for scope in ["backend", "frontend", "package"] {
      let scope_prefix = scope + "."
      if path.has_prefix(scope_prefix) {
        return "Unexpected" +
          " key '" +
          path[scope_prefix.length():].to_owned() +
          "' found in proton.project.json field `" +
          scope +
          "`."
      }
    }
    "unknown field: " + path
  }
}

///|
impl Show for ProjectConfigError with fn output(self, logger) {
  logger.write_string(self.message())
}
