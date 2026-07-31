///|
/// Failures while loading user configuration or internal runtime manifests.
pub(all) suberror BootstrapError {
  ProjectConfig(@proton_config.ProjectConfigError)
} derive(Debug, Eq)

///|
pub fn BootstrapError::message(self : BootstrapError) -> String {
  match self {
    ProjectConfig(error) => error.message()
  }
}

///|
impl Show for BootstrapError with fn output(self, logger) {
  logger.write_string(self.message())
}
