///|
/// Loads this application's identifier from managed Proton metadata.
///
/// Development runs read `proton.project.json`. Packaged applications read
/// the sanitized `proton-package.json` staged beside the executable.
pub fn App::load_config(self : App) -> App {
  match load_managed_application_identifier() {
    Ok(identifier) => self.set_application_identity(ProjectConfig(identifier))
    Err(error) => {
      self.validation_errors.push(error)
      self
    }
  }
}

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
          message="is already configured; use either .load_config() or .identifier(...), not both",
        ),
      )
    None => self.application_identity = Some(identity)
  }
  self
}

///|
fn App::application_identifier(self : App) -> String raise AppPathError {
  match self.application_identity {
    Some(ProjectConfig(identifier) | Explicit(identifier)) => identifier
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
fn load_managed_application_identifier() -> Result[
  String,
  AppConfigurationError,
] {
  match packaged_application_manifest_path() {
    Some(path) => load_packaged_application_identifier(path)
    None => load_project_application_identifier(project_config_path())
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
fn load_project_application_identifier(
  path : String,
) -> Result[String, AppConfigurationError] {
  try @proton_config.load_project_config_from_file(path) catch {
    error => Err(InvalidSetting(name="config", message=error.message()))
  } noraise {
    config => Ok(config.identifier())
  }
}

///|
fn load_packaged_application_identifier(
  path : String,
) -> Result[String, AppConfigurationError] {
  let source = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    error =>
      return Err(
        InvalidSetting(
          name="config",
          message="failed to read packaged application metadata: " +
            @debug.render(Repr(error)),
        ),
      )
  }
  packaged_application_identifier_from_json(source)
}

///|
fn packaged_application_identifier_from_json(
  source : String,
) -> Result[String, AppConfigurationError] {
  let json = @json.parse(source) catch {
    error =>
      return Err(
        InvalidSetting(
          name="config",
          message="invalid packaged application metadata: " + error.to_string(),
        ),
      )
  }
  guard json is Object(fields) else {
    return Err(
      InvalidSetting(
        name="config",
        message="invalid packaged application metadata: expected an object",
      ),
    )
  }
  guard fields.get("identifier") is Some(String(identifier)) else {
    return Err(
      InvalidSetting(
        name="config",
        message="packaged application metadata requires identifier",
      ),
    )
  }
  validate_application_identifier(identifier)
}
