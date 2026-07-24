///|
pub(all) suberror PackageUsageError {
  InvalidArguments(message~ : String, usage_is_embedded~ : Bool)
  UnsupportedTarget(target~ : String)
  MissingOptionValue(option~ : String)
} derive(Debug, Eq)

///|
pub(all) suberror PackageConfigError {
  NotFound(path~ : String)
  Invalid(path~ : String, error~ : @proton_config.ProjectConfigError)
  BundleInactive
  BundleMissing
  MissingField(field~ : String)
} derive(Debug, Eq)

///|
pub(all) suberror PackagePlanError {
  InvalidProductName(reason~ : String)
  InvalidIdentifier(identifier~ : String, reason~ : String)
  InvalidVersion(version~ : String, reason~ : String)
  UnsupportedPlatform
  UnsupportedResourceGlob(path~ : String)
  MissingInput(path~ : String)
  MissingExecutable(path~ : String)
  InputOutsideProject(path~ : String)
  MissingIcon(path~ : String)
} derive(Debug, Eq)

///|
pub(all) suberror PackageRuntimeError {
  ManifestMissing(path~ : String)
  ManifestInvalid(path~ : String, detail~ : String)
  ManifestField(path~ : String, field~ : String)
  PlatformMismatch(expected~ : String, actual~ : String)
  DirectoryMissing(path~ : String)
  HelperMissing(path~ : String)
} derive(Debug, Eq)

///|
pub(all) suberror PackageFileSystemError {
  CreateDirectory(path~ : String, detail~ : String)
  Remove(path~ : String, detail~ : String)
  Copy(source~ : String, destination~ : String, detail~ : String)
  Read(path~ : String, detail~ : String)
  Write(path~ : String, detail~ : String)
  InvalidSource(path~ : String)
} derive(Debug, Eq)

///|
pub(all) suberror PackageToolError {
  Start(tool~ : String, detail~ : String)
  Exit(tool~ : String, code~ : Int, detail~ : String)
} derive(Debug, Eq)

///|
pub(all) suberror MacosSigningError {
  InvalidConfiguration(detail~ : String)
  MissingTarget(path~ : String)
  ToolFailure(stage~ : String, detail~ : String)
  Verification(detail~ : String)
} derive(Debug, Eq)

///|
pub(all) suberror WindowsPackagingError {
  InvalidConfiguration(detail~ : String)
  MissingTarget(path~ : String)
  ToolFailure(stage~ : String, detail~ : String)
  Verification(detail~ : String)
} derive(Debug, Eq)

///|
pub fn PackageUsageError::message(self : PackageUsageError) -> String {
  match self {
    InvalidArguments(message~, ..) => message
    UnsupportedTarget(target~) => "unsupported package target: " + target
    MissingOptionValue(option~) => option + " requires a value"
  }
}

///|
pub fn PackageConfigError::message(self : PackageConfigError) -> String {
  match self {
    NotFound(path~) => "proton package config not found: " + path
    Invalid(path~, error~) =>
      "invalid proton package config " + path + ": " + error.message()
    BundleInactive => "bundle.active must be true for proton package"
    BundleMissing => "bundle config is required for proton package"
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
    UnsupportedPlatform => "proton package currently supports macOS and Windows"
    UnsupportedResourceGlob(path~) =>
      "unsupported bundle.resources glob: " + path
    MissingInput(path~) => "package input is missing: " + path
    MissingExecutable(path~) =>
      "package release executable not found under " +
      path +
      "; run proton package without --no-build first"
    InputOutsideProject(path~) =>
      "package input must stay inside the project: " + path
    MissingIcon(path~) => "macOS icon is missing: " + path
  }
}

///|
pub fn PackageRuntimeError::message(self : PackageRuntimeError) -> String {
  match self {
    ManifestMissing(path~) => "active Proton runtime is missing: " + path
    ManifestInvalid(path~, detail~) =>
      "invalid active Proton runtime manifest " + path + ": " + detail
    ManifestField(path~, field~) =>
      "active Proton runtime manifest " +
      path +
      " missing string field: " +
      field
    PlatformMismatch(expected~, actual~) =>
      "active Proton runtime platform mismatch: expected " +
      expected +
      ", got " +
      actual
    DirectoryMissing(path~) =>
      "active Proton runtime directory is missing: " + path
    HelperMissing(path~) => "active Proton runtime helper is missing: " + path
  }
}

///|
pub fn PackageFileSystemError::message(self : PackageFileSystemError) -> String {
  match self {
    CreateDirectory(path~, detail~) =>
      "failed to create directory " + path + ": " + detail
    Remove(path~, detail~) => "failed to remove " + path + ": " + detail
    Copy(source~, destination~, detail~) =>
      "failed to copy " + source + " to " + destination + ": " + detail
    Read(path~, detail~) => "failed to read " + path + ": " + detail
    Write(path~, detail~) => "failed to write " + path + ": " + detail
    InvalidSource(path~) => "package input is not a file or directory: " + path
  }
}

///|
pub fn PackageToolError::message(self : PackageToolError) -> String {
  match self {
    Start(tool~, detail~) => "failed to run " + tool + ": " + detail
    Exit(tool~, code~, detail~) =>
      tool +
      " exited with code " +
      code.to_string() +
      (if detail == "" { "" } else { ": " + detail })
  }
}

///|
pub fn MacosSigningError::message(self : MacosSigningError) -> String {
  match self {
    InvalidConfiguration(detail~) => detail
    MissingTarget(path~) => "required macOS signing target is missing: " + path
    ToolFailure(stage~, detail~) => stage + " failed: " + detail
    Verification(detail~) => "macOS signing verification failed: " + detail
  }
}

///|
pub fn WindowsPackagingError::message(self : WindowsPackagingError) -> String {
  match self {
    InvalidConfiguration(detail~) => detail
    MissingTarget(path~) => "required Windows target is missing: " + path
    ToolFailure(stage~, detail~) => stage + " failed: " + detail
    Verification(detail~) => "Windows package verification failed: " + detail
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

///|
impl Show for PackageRuntimeError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for PackageFileSystemError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for PackageToolError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for MacosSigningError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for WindowsPackagingError with fn output(self, logger) {
  logger.write_string(self.message())
}
