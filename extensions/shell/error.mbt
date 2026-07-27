///|
/// Failures while launching targets through the operating-system shell.
suberror ShellError {
  UnsupportedPlatform
  EmptyTarget(field~ : String)
  LaunchFailed(operation~ : String, target~ : String)
} derive(Debug, Eq)

///|
fn ShellError::message(self : ShellError) -> String {
  match self {
    UnsupportedPlatform =>
      "shell extension currently supports Windows native builds only"
    EmptyTarget(field~) => field + " must not be empty"
    LaunchFailed(operation~, target~) =>
      "shell." + operation + " failed for target: " + target
  }
}

///|
impl Show for ShellError with fn output(self, logger) {
  logger.write_string(self.message())
}
