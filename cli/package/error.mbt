///|
pub(all) suberror PackageUsageError {
  UnsupportedTarget(target~ : String)
} derive(Debug, Eq)

///|
pub extend PackageUsageError with Eq::{not_equal, equal}

///|
pub extend PackageUsageError with Debug::{to_repr}

///|
pub extend PackageUsageError with Show::{to_string, output}

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
pub(all) suberror PackagePlanError {
  InvalidProductName(reason~ : String)
  InvalidIdentifier(identifier~ : String, reason~ : String)
  InvalidVersion(version~ : String, reason~ : String)
  UnsupportedTargetForPlatform(target~ : String, platform~ : String)
  MissingExecutable(path~ : String)
} derive(Debug, Eq)

///|
pub extend PackagePlanError with Eq::{not_equal, equal}

///|
pub extend PackagePlanError with Debug::{to_repr}

///|
pub extend PackagePlanError with Show::{to_string, output}

///|
pub fn PackageUsageError::message(self : PackageUsageError) -> String {
  match self {
    UnsupportedTarget(target~) => "unsupported package target: " + target
  }
}

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
pub fn PackagePlanError::message(self : PackagePlanError) -> String {
  match self {
    InvalidProductName(reason~) => "invalid product_name: " + reason
    InvalidIdentifier(identifier~, reason~) =>
      "invalid identifier " + identifier + ": " + reason
    InvalidVersion(version~, reason~) =>
      "invalid bundle version " + version + ": " + reason
    UnsupportedTargetForPlatform(target~, platform~) =>
      "package target " + target + " is not supported on " + platform
    MissingExecutable(path~) =>
      "Moon reported a package executable that does not exist: " + path
  }
}

///|
impl Show for PackageUsageError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for PackageConfigError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for PackagePlanError with fn output(self, logger) {
  logger.write_string(self.message())
}
