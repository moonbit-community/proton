///|
/// Typed configuration shared by Proton applications and the CLI.
pub using @proton_config {
  type AppConfig,
  type BackendConfig,
  type FrontendConfig,
  type PackageConfig,
  type PackagePlatforms,
  type PlatformPackageConfig,
  type SignConfig,
  type DocumentType,
  type AppConfigError,
}

///|
/// Supplies a complete configuration snapshot.
/// Packaged applications also verify the identifier against bundled metadata.
pub fn App::with_config(self : App, config : AppConfig) -> App {
  try {
    config.validate()
    let identifier = match
      resolve_explicit_application_identifier(config.identifier) {
      Ok(identifier) => identifier
      Err(error) =>
        raise @proton_config.InvalidField(
          path="identifier",
          expectation=error.message(),
        )
    }
    let config = { ..config.copy(), identifier, }
    self.set_application_identity(Configured(config))
  } catch {
    error => {
      self.record_config_failure(error)
      self.validation_errors.push(
        InvalidSetting(name="config", message=error.message()),
      )
      self
    }
  }
}

///|
/// Returns an independent copy of the loaded configuration. No file is read.
pub fn App::config(self : App) -> AppConfig raise AppConfigError {
  self.loaded_config().copy()
}

///|
fn App::loaded_config(self : App) -> AppConfig raise AppConfigError {
  match self.application_identity {
    Some(Configured(config)) => config
    Some(ConfigFailed(error)) => raise error
    _ =>
      raise @proton_config.MissingField(
        path="application config; call load_config() or with_config()",
      )
  }
}

///|
fn App::record_config_failure(self : App, error : AppConfigError) -> Unit {
  if self.application_identity is None {
    self.application_identity = Some(ConfigFailed(error))
  }
}
