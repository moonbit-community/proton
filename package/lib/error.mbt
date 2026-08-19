///|
pub(all) suberror PackagePlanError {
  InvalidProductName(reason~ : String)
  InvalidIdentifier(identifier~ : String, reason~ : String)
  InvalidVersion(version~ : String, reason~ : String)
  UnsupportedFormat(format~ : String)
  UnsupportedFormatForPlatform(format~ : String, platform~ : String)
  MissingExecutable(path~ : String)
  MissingInput(path~ : String)
  MissingIcon(path~ : String)
  InvalidPayload(detail~ : String)
} derive(Debug, Eq)

///|
pub extend PackagePlanError with Eq::{not_equal, equal}

///|
pub extend PackagePlanError with Debug::{to_repr}

///|
pub fn PackagePlanError::message(self : PackagePlanError) -> String {
  match self {
    InvalidProductName(reason~) => "invalid product_name: " + reason
    InvalidIdentifier(identifier~, reason~) =>
      "invalid identifier " + identifier + ": " + reason
    InvalidVersion(version~, reason~) =>
      "invalid version " + version + ": " + reason
    UnsupportedFormat(format~) => "unsupported package format: " + format
    UnsupportedFormatForPlatform(format~, platform~) =>
      "package format " + format + " is not supported on " + platform
    MissingExecutable(path~) => "package executable is missing: " + path
    MissingInput(path~) => "package input is missing: " + path
    MissingIcon(path~) => "package icon is missing: " + path
    InvalidPayload(detail~) => "invalid package payload: " + detail
  }
}

///|
impl Show for PackagePlanError with fn output(self, logger) {
  logger.write_string(self.message())
}

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
pub extend PackageFileSystemError with Eq::{not_equal, equal}

///|
pub extend PackageFileSystemError with Debug::{to_repr}

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
impl Show for PackageFileSystemError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub(all) suberror PackageToolError {
  Start(tool~ : String, detail~ : String)
  Exit(tool~ : String, code~ : Int, detail~ : String)
} derive(Debug, Eq)

///|
pub extend PackageToolError with Eq::{not_equal, equal}

///|
pub extend PackageToolError with Debug::{to_repr}

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
impl Show for PackageToolError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub(all) suberror MacosSigningError {
  InvalidConfiguration(detail~ : String)
  ToolFailure(stage~ : String, detail~ : String)
  Verification(detail~ : String)
} derive(Debug, Eq)

///|
pub extend MacosSigningError with Eq::{not_equal, equal}

///|
pub extend MacosSigningError with Debug::{to_repr}

///|
pub fn MacosSigningError::message(self : MacosSigningError) -> String {
  match self {
    InvalidConfiguration(detail~) => detail
    ToolFailure(stage~, detail~) => stage + " failed: " + detail
    Verification(detail~) => "macOS signing verification failed: " + detail
  }
}

///|
impl Show for MacosSigningError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub(all) suberror WindowsPackagingError {
  InvalidConfiguration(detail~ : String)
  MissingTarget(path~ : String)
  ToolFailure(stage~ : String, detail~ : String)
  Verification(detail~ : String)
} derive(Debug, Eq)

///|
pub extend WindowsPackagingError with Eq::{not_equal, equal}

///|
pub extend WindowsPackagingError with Debug::{to_repr}

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
impl Show for WindowsPackagingError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub(all) suberror LinuxPackagingError {
  InvalidConfiguration(detail~ : String)
  ToolFailure(stage~ : String, detail~ : String)
} derive(Debug, Eq)

///|
pub extend LinuxPackagingError with Eq::{not_equal, equal}

///|
pub extend LinuxPackagingError with Debug::{to_repr}

///|
pub fn LinuxPackagingError::message(self : LinuxPackagingError) -> String {
  match self {
    InvalidConfiguration(detail~) => detail
    ToolFailure(stage~, detail~) => stage + " failed: " + detail
  }
}

///|
impl Show for LinuxPackagingError with fn output(self, logger) {
  logger.write_string(self.message())
}
