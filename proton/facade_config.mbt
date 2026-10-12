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
/// Loads the complete configuration from the current application environment.
/// Development uses proton.project.json; packaged applications use bundled
/// proton-package.json. Read and validation errors are reported immediately.
pub fn load_config() -> AppConfig raise AppConfigError {
  let path = packaged_application_manifest_path().unwrap_or_else(
    project_config_path,
  )
  AppConfig::load(path)
}

///|
/// Supplies a complete configuration snapshot.
/// Packaged applications also verify the identifier against bundled metadata.
pub fn App::config(self : App, config : AppConfig) -> App {
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
      self.validation_errors.push(
        InvalidSetting(name="config", message=error.message()),
      )
      self
    }
  }
}

///|
fn App::configured_config(self : App) -> AppConfig raise AppConfigError {
  match self.application_identity {
    Some(Configured(config)) => config
    _ =>
      raise @proton_config.MissingField(
        path="application config; call config(config)",
      )
  }
}
