///|
/// Sets the canonical identifier for an application without project metadata.
pub fn App::identifier(self : App, identifier : String) -> Unit {
  let identifier = resolve_explicit_application_identifier(identifier) catch {
    error => return self.validation_errors.push(error)
  }
  self.set_application_identity(Explicit(identifier))
}

///|
fn resolve_explicit_application_identifier(
  identifier : String,
) -> String raise AppConfigurationError {
  let identifier = validate_application_identifier(identifier)
  guard packaged_application_manifest_path() is Some(path) else {
    return identifier
  }
  verify_packaged_application_identifier(
    identifier,
    load_packaged_application_identifier(path),
  )
}

///|
fn verify_packaged_application_identifier(
  identifier : String,
  packaged_identifier : String,
) -> String raise AppConfigurationError {
  if identifier == packaged_identifier {
    identifier
  } else {
    raise InvalidSetting(
      name="identifier",
      message="does not match packaged application metadata (expected " +
        packaged_identifier +
        ")",
    )
  }
}

///|
fn App::set_application_identity(
  self : App,
  identity : ApplicationIdentitySource,
) -> Unit {
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
) -> String raise AppConfigurationError {
  try @proton_config.validate_application_identifier(identifier) catch {
    @proton_config.InvalidField(expectation~, ..) =>
      raise InvalidSetting(name="identifier", message=expectation)
    error => raise InvalidSetting(name="identifier", message=error.message())
  } noraise {
    identifier => identifier
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
) -> String raise AppConfigurationError {
  try @proton_config.AppConfig::load(path) catch {
    error => raise InvalidSetting(name="config", message=error.message())
  } noraise {
    config => config.identifier
  }
}
