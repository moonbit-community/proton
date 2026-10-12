///|
/// Sets the canonical identifier for an application without project metadata.
pub fn App::identifier(self : App, identifier : String) -> App {
  match resolve_explicit_application_identifier(identifier) {
    Ok(identifier) => self.set_application_identity(Explicit(identifier))
    Err(error) => {
      self.validation_errors.push(error)
      self
    }
  }
}

///|
fn resolve_explicit_application_identifier(
  identifier : String,
) -> Result[String, AppConfigurationError] {
  let identifier = match validate_application_identifier(identifier) {
    Ok(identifier) => identifier
    Err(error) => return Err(error)
  }
  guard packaged_application_manifest_path() is Some(path) else {
    return Ok(identifier)
  }
  match load_packaged_application_identifier(path) {
    Err(error) => Err(error)
    Ok(packaged_identifier) =>
      verify_packaged_application_identifier(identifier, packaged_identifier)
  }
}

///|
fn verify_packaged_application_identifier(
  identifier : String,
  packaged_identifier : String,
) -> Result[String, AppConfigurationError] {
  if identifier == packaged_identifier {
    Ok(identifier)
  } else {
    Err(
      InvalidSetting(
        name="identifier",
        message="does not match packaged application metadata (expected " +
          packaged_identifier +
          ")",
      ),
    )
  }
}

///|
fn App::set_application_identity(
  self : App,
  identity : ApplicationIdentitySource,
) -> App {
  match self.application_identity {
    Some(_) =>
      self.validation_errors.push(
        InvalidSetting(
          name="identifier",
          message="is already configured; use only one of .config(config) or .identifier(...)",
        ),
      )
    None => self.application_identity = Some(identity)
  }
  self
}

///|
fn App::application_identifier(self : App) -> String raise AppPathError {
  match self.application_identity {
    Some(Configured(config)) => config.identifier
    Some(Explicit(identifier)) => identifier
    None => raise MissingApplicationIdentifier
  }
}

///|
fn validate_application_identifier(
  identifier : String,
) -> Result[String, AppConfigurationError] {
  try @proton_config.validate_application_identifier(identifier) catch {
    @proton_config.InvalidField(expectation~, ..) =>
      Err(InvalidSetting(name="identifier", message=expectation))
    error => Err(InvalidSetting(name="identifier", message=error.message()))
  } noraise {
    identifier => Ok(identifier)
  }
}

///|
fn project_config_path() -> String {
  match @env.get_env_var("PROTON_PROJECT_CONFIG") {
    Some(path) if path.trim().to_owned() != "" => {
      let path : @mbpath.Path = path.trim().to_owned()
      path.resolve().to_string()
    }
    _ =>
      @mbpath.Path(runtime_resource_dir())
      .join("proton.project.json")
      .normalize()
      .to_string()
  }
}

///|
fn load_packaged_application_identifier(
  path : String,
) -> Result[String, AppConfigurationError] {
  try @proton_config.AppConfig::load(path) catch {
    error => Err(InvalidSetting(name="config", message=error.message()))
  } noraise {
    config => Ok(config.identifier)
  }
}
