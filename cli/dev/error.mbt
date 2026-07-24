///|
/// Invalid `proton dev` command-line input.
pub(all) suberror DevUsageError {
  InvalidNonNegativeInteger(option~ : String, value~ : String)
} derive(Debug, Eq)

///|
/// Invalid project configuration used by `proton dev`.
pub(all) suberror DevConfigError {
  NotFound(path~ : String)
  Invalid(path~ : String, error~ : @proton_config.ProjectConfigError)
  FrontendDirectoryMissing(path~ : String)
  FrontendDirectoryNotDirectory(path~ : String)
} derive(Debug, Eq)

///|
/// Failures while locating and validating the native development runtime.
pub(all) suberror DevRuntimeError {
  NativeDistOverride(detail~ : String)
  Setup(detail~ : String)
  ManifestMissing(path~ : String)
  ManifestInvalid(path~ : String, detail~ : String)
  ManifestField(path~ : String, field~ : String)
  PlatformMismatch(expected~ : String, actual~ : String)
  DirectoryMissing(label~ : String, path~ : String)
  HelperMissing(label~ : String, path~ : String)
  SetupRequired(detail~ : String)
} derive(Debug, Eq)

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
  FrontendExited(code~ : Int)
  Timeout(url~ : String)
} derive(Debug, Eq)

///|
/// Failures while starting or running child processes owned by `proton dev`.
pub(all) suberror DevProcessError {
  Start(role~ : String, detail~ : String)
  Exit(role~ : String, code~ : Int)
} derive(Debug, Eq)

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
    FrontendDirectoryMissing(path~) => "frontend cwd does not exist: " + path
    FrontendDirectoryNotDirectory(path~) =>
      "frontend cwd is not a directory: " + path
  }
}

///|
pub fn DevRuntimeError::message(self : DevRuntimeError) -> String {
  match self {
    NativeDistOverride(detail~) =>
      detail +
      "\n\nPROTON_NATIVE_DIST is set; unset it or point it at a valid Proton runtime."
    Setup(detail~) => "failed to set up Proton runtime: " + detail
    ManifestMissing(path~) => "active Proton runtime is missing: " + path
    ManifestInvalid(path~, detail~) =>
      "invalid Proton runtime manifest " + path + ": " + detail
    ManifestField(path~, field~) =>
      "Proton runtime manifest " + path + " missing string field: " + field
    PlatformMismatch(expected~, actual~) =>
      "active Proton runtime platform mismatch: expected " +
      expected +
      ", got " +
      actual
    DirectoryMissing(label~, path~) => label + " directory is missing: " + path
    HelperMissing(label~, path~) => label + " helper is missing: " + path
    SetupRequired(detail~) =>
      detail +
      "\n\nRun `proton_cli cef setup` first, or retry with `proton_cli dev --setup`."
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
