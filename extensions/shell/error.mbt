///|
/// Failures while launching targets through the operating-system shell.
suberror ShellError {
  UnsupportedPlatform
  EmptyTarget(field~ : String)
  LaunchFailed(operation~ : String, target~ : String)
} derive(Debug, Eq)

///|
pub extend ShellError with Eq::{not_equal, equal}

///|
pub extend ShellError with Debug::{to_repr}

///|
pub extend ShellError with Show::{to_string, output}

///|
fn ShellError::message(self : ShellError) -> String {
  match self {
    UnsupportedPlatform =>
      "shell extension currently supports Windows, macOS, and Linux native builds"
    EmptyTarget(field~) => field + " must not be empty"
    LaunchFailed(operation~, target~) =>
      "shell." + operation + " failed for target: " + target
  }
}

///|
impl Show for ShellError with fn output(self, logger) {
  logger.write_string(self.message())
}
