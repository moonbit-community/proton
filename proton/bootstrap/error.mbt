///|
/// Failures while loading user configuration or internal runtime manifests.
pub(all) suberror BootstrapError {
  ProjectConfig(@proton_config.ProjectConfigError)
  ManifestRead(path~ : String, detail~ : String)
  InvalidJson(context~ : String, detail~ : String)
  MissingField(path~ : String)
  InvalidField(path~ : String, expectation~ : String)
  UnsupportedField(path~ : String, reason~ : String)
  UnsupportedValue(path~ : String, value~ : String)
} derive(Debug, Eq)

///|
pub fn BootstrapError::message(self : BootstrapError) -> String {
  match self {
    ProjectConfig(error) => error.message()
    ManifestRead(path~, detail~) => "failed to read " + path + ": " + detail
    InvalidJson(context~, detail~) =>
      "failed to decode " + context + ": " + detail
    MissingField(path~) => "missing required field: " + path
    InvalidField(path~, expectation~) => path + " " + expectation
    UnsupportedField(path~, reason~) => path + " is not supported: " + reason
    UnsupportedValue(path~, value~) => "unsupported " + path + ": " + value
  }
}

///|
impl Show for BootstrapError with fn output(self, logger) {
  logger.write_string(self.message())
}
