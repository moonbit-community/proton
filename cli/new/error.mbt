///|
/// Invalid template selection or a failed moon-new invocation.
pub(all) suberror NewProjectError {
  InvalidTemplate(String)
  GeneratorFailed(Int32)
} derive(Debug)

///|
pub extend NewProjectError with @debug.Debug::{to_repr}

///|
impl Show for NewProjectError with fn output(self, logger) {
  match self {
    InvalidTemplate(name) =>
      logger.write_string(
        "unknown project template \{name}; expected minimal or isomorphic",
      )
    GeneratorFailed(code) =>
      logger.write_string(
        "moon-new exited with status \{code}; see its diagnostic above",
      )
  }
}

///|
pub extend NewProjectError with Show::{to_string, output}
