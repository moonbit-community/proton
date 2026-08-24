///|
pub(all) suberror PackageConfigError {
  NotFound(path~ : String)
  Invalid(path~ : String, error~ : @proton_config.ProjectConfigError)
  PackageMissing
  MissingField(field~ : String)
} derive(Debug, Eq)

///|
pub extend PackageConfigError with Eq::{not_equal, equal}

///|
pub extend PackageConfigError with Debug::{to_repr}

///|
pub extend PackageConfigError with Show::{to_string, output}

///|
pub fn PackageConfigError::message(self : PackageConfigError) -> String {
  match self {
    NotFound(path~) => "proton package config not found: " + path
    Invalid(path~, error~) =>
      "invalid proton package config " + path + ": " + error.message()
    PackageMissing => "package config is required for proton package"
    MissingField(field~) => field + " is required for proton package"
  }
}

///|
impl Show for PackageConfigError with fn output(self, logger) {
  logger.write_string(self.message())
}
