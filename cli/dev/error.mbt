///|
/// Invalid `proton dev` command-line input.
pub(all) suberror DevUsageError {
  InvalidNonNegativeInteger(option~ : String, value~ : String)
} derive(Debug, Eq)

///|
pub extend DevUsageError with Eq::{not_equal, equal}

///|
pub extend DevUsageError with Debug::{to_repr}

///|
pub extend DevUsageError with Show::{to_string, output}

///|
/// Invalid project configuration used by `proton dev`.
pub(all) suberror DevConfigError {
  NotFound(path~ : String)
  Invalid(path~ : String, error~ : @proton_config.ProjectConfigError)
  FrontendCommandMissing
  FrontendDirectoryMissing(path~ : String)
  FrontendDirectoryNotDirectory(path~ : String)
  BackendDirectoryMissing(path~ : String)
  BackendDirectoryNotDirectory(path~ : String)
} derive(Debug, Eq)

///|
pub extend DevConfigError with Eq::{not_equal, equal}

///|
pub extend DevConfigError with Debug::{to_repr}

///|
pub extend DevConfigError with Show::{to_string, output}

///|
/// Failures while locating and validating the native development runtime.
pub(all) suberror DevRuntimeError {
  Setup(detail~ : String)
  DirectoryMissing(label~ : String, path~ : String)
  HelperMissing(label~ : String, path~ : String)
  SetupRequired(detail~ : String)
} derive(Debug, Eq)

///|
pub extend DevRuntimeError with Eq::{not_equal, equal}

///|
pub extend DevRuntimeError with Debug::{to_repr}

///|
pub extend DevRuntimeError with Show::{to_string, output}

///|
/// Invalid frontend URLs and readiness failures.
pub(all) suberror DevServerError {
  MissingScheme(url~ : String)
  UnsupportedScheme(url~ : String)
  InvalidOrigin(url~ : String)
  InvalidHost(authority~ : String)
  EmptyHost
  InvalidPort(value~ : String)
  PortOutOfRange(value~ : String)
  ReadyProbeUnavailable
  FrontendUrlInUse(url~ : String)
  FrontendExited(code~ : Int)
  Timeout(url~ : String)
} derive(Debug, Eq)

///|
pub extend DevServerError with Eq::{not_equal, equal}

///|
pub extend DevServerError with Debug::{to_repr}

///|
pub extend DevServerError with Show::{to_string, output}

///|
/// Failures while starting or running child processes owned by `proton dev`.
pub(all) suberror DevProcessError {
  Start(role~ : String, detail~ : String)
  Exit(role~ : String, code~ : Int)
} derive(Debug, Eq)

///|
pub extend DevProcessError with Eq::{not_equal, equal}

///|
pub extend DevProcessError with Debug::{to_repr}

///|
pub extend DevProcessError with Show::{to_string, output}

///|
pub fn DevUsageError::message(self : DevUsageError) -> String {
  match self {
    InvalidNonNegativeInteger(option~, value~) =>
      option + " must be a non-negative integer: " + value
  }
}

///|
pub fn DevConfigError::message(self : DevConfigError) -> String {
  match self {
    NotFound(path~) => "proton dev config not found: " + path
    Invalid(path~, error~) =>
      "invalid proton dev config " + path + ": " + error.message()
    FrontendCommandMissing =>
      "frontend.before_dev is required when proton_cli dev manages frontend.dev_url\n\nConfigure frontend.before_dev, pass --command, or use --no-frontend to connect to an existing server."
    FrontendDirectoryMissing(path~) => "frontend path does not exist: " + path
    FrontendDirectoryNotDirectory(path~) =>
      "frontend path is not a directory: " + path
    BackendDirectoryMissing(path~) => "backend path does not exist: " + path
    BackendDirectoryNotDirectory(path~) =>
      "backend path is not a directory: " + path
  }
}

///|
pub fn DevRuntimeError::message(self : DevRuntimeError) -> String {
  match self {
    Setup(detail~) => "failed to set up Proton runtime: " + detail
    DirectoryMissing(label~, path~) => label + " directory is missing: " + path
    HelperMissing(label~, path~) => label + " helper is missing: " + path
    SetupRequired(detail~) =>
      detail +
      "\n\nRun `moonx moonbit-community/proton_cefsetup`, or retry with `proton_cli dev --setup`."
  }
}

///|
pub fn DevServerError::message(self : DevServerError) -> String {
  match self {
    MissingScheme(url~) =>
      "frontend dev URL must include http:// or https://: " + url
    UnsupportedScheme(url~) => "frontend dev URL must be http or https: " + url
    InvalidOrigin(url~) => "frontend dev URL has invalid origin: " + url
    InvalidHost(authority~) => "invalid frontend dev URL host: " + authority
    EmptyHost => "frontend dev URL host must not be empty"
    InvalidPort(value~) => "frontend dev URL port must be an integer: " + value
    PortOutOfRange(value~) => "frontend dev URL port is out of range: " + value
    ReadyProbeUnavailable =>
      "--ready-path requires curl on PATH; install curl or omit --ready-path to use TCP readiness"
    FrontendUrlInUse(url~) =>
      "frontend dev URL is already in use: " +
      url +
      "\n\nStop the existing server, change frontend.dev_url and frontend.before_dev, or use --no-frontend to connect to the existing server."
    FrontendExited(code~) =>
      "frontend command exited before the dev server became ready: " +
      code.to_string()
    Timeout(url~) => "timed out waiting for frontend dev server: " + url
  }
}

///|
pub fn DevProcessError::message(self : DevProcessError) -> String {
  match self {
    Start(role~, detail~) => "failed to start " + role + ": " + detail
    Exit(role~, code~) => role + " exited with code " + code.to_string()
  }
}

///|
impl Show for DevUsageError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for DevConfigError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for DevRuntimeError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for DevServerError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for DevProcessError with fn output(self, logger) {
  logger.write_string(self.message())
}
