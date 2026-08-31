///|
/// Failures while reading application metadata managed by Proton tooling.
pub(all) suberror AppMetadataError {
  MissingPackageMetadata
  MissingField(field~ : String)
  InvalidMetadata(detail~ : String)
} derive(Debug, Eq)

///|
pub extend AppMetadataError with Eq::{not_equal, equal}

///|
pub extend AppMetadataError with Debug::{to_repr}

///|
pub fn AppMetadataError::message(self : AppMetadataError) -> String {
  match self {
    MissingPackageMetadata => "application package metadata is not configured"
    MissingField(field~) => "application package metadata requires " + field
    InvalidMetadata(detail~) =>
      "invalid application package metadata: " + detail
  }
}

///|
impl Show for AppMetadataError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub extend AppMetadataError with Show::{to_string, output}

///|
priv struct ApplicationMetadata {
  name : String
  version : String
}

///|
/// Returns the product name from managed development or packaged metadata.
pub fn App::name(self : App) -> String raise AppMetadataError {
  self.application_metadata().name
}

///|
/// Returns the application version from managed development or packaged
/// metadata.
pub fn App::version(self : App) -> String raise AppMetadataError {
  self.application_metadata().version
}

///|
fn App::application_metadata(
  self : App,
) -> ApplicationMetadata raise AppMetadataError {
  match packaged_application_manifest_path() {
    Some(path) => load_packaged_application_metadata(path)
    None =>
      match self.application_identity {
        Some(ProjectConfig(_)) =>
          load_project_application_metadata(project_config_path())
        Some(Explicit(_)) | None => raise MissingPackageMetadata
      }
  }
}

///|
fn load_project_application_metadata(
  path : String,
) -> ApplicationMetadata raise AppMetadataError {
  let config = @proton_config.load_project_config_from_file(path) catch {
    error => raise InvalidMetadata(detail=error.message())
  }
  project_application_metadata(config)
}

///|
fn project_application_metadata(
  config : @proton_config.ProjectConfig,
) -> ApplicationMetadata raise AppMetadataError {
  guard config.package_config() is Some(package_config) else {
    raise MissingPackageMetadata
  }
  ApplicationMetadata::{
    name: normalize_application_metadata_string(
      package_config.product_name,
      "product_name",
    ),
    version: normalize_application_metadata_string(
      package_config.version(),
      "version",
    ),
  }
}

///|
fn load_packaged_application_metadata(
  path : String,
) -> ApplicationMetadata raise AppMetadataError {
  let source = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    error =>
      raise InvalidMetadata(
        detail="failed to read " + path + ": " + @debug.render(Repr(error)),
      )
  }
  packaged_application_metadata_from_json(source)
}

///|
fn packaged_application_metadata_from_json(
  source : String,
) -> ApplicationMetadata raise AppMetadataError {
  let json = @json.parse(source) catch {
    error => raise InvalidMetadata(detail=error.to_string())
  }
  guard json is Object(fields) else {
    raise InvalidMetadata(detail="expected an object")
  }
  let name = required_application_metadata_string(fields, "product_name")
  let version = required_application_metadata_string(fields, "version")
  ApplicationMetadata::{ name, version, }
}

///|
fn required_application_metadata_string(
  fields : Map[String, Json],
  field : String,
) -> String raise AppMetadataError {
  guard fields.get(field) is Some(String(value)) else {
    raise MissingField(field~)
  }
  normalize_application_metadata_string(value, field)
}

///|
fn normalize_application_metadata_string(
  value : String,
  field : String,
) -> String raise AppMetadataError {
  let value = value.trim().to_owned()
  guard value != "" else { raise MissingField(field~) }
  value
}
