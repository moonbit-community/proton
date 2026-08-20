///|
pub(all) suberror BundlePlanError {
  UnsupportedResourceGlob(path~ : String)
  MissingInput(path~ : String)
  NotLaunchableMachO(path~ : String, filetype~ : Int)
  InputOutsideBase(path~ : String)
} derive(Debug, Eq)

///|
pub extend BundlePlanError with Eq::{not_equal, equal}

///|
pub extend BundlePlanError with Debug::{to_repr}

///|
pub extend BundlePlanError with Show::{to_string, output}

///|
pub(all) suberror BundleRuntimeError {
  ExecutableMissing(path~ : String)
  HelperMissing(path~ : String)
} derive(Debug, Eq)

///|
pub extend BundleRuntimeError with Eq::{not_equal, equal}

///|
pub extend BundleRuntimeError with Debug::{to_repr}

///|
pub extend BundleRuntimeError with Show::{to_string, output}

///|
pub(all) suberror BundleFileSystemError {
  CreateDirectory(path~ : String, detail~ : String)
  Copy(source~ : String, destination~ : String, detail~ : String)
  Read(path~ : String, detail~ : String)
  Write(path~ : String, detail~ : String)
} derive(Debug, Eq)

///|
pub extend BundleFileSystemError with Eq::{not_equal, equal}

///|
pub extend BundleFileSystemError with Debug::{to_repr}

///|
pub extend BundleFileSystemError with Show::{to_string, output}

///|
pub(all) suberror BundleToolError {
  Exit(tool~ : String, code~ : Int, detail~ : String)
} derive(Debug, Eq)

///|
pub extend BundleToolError with Eq::{not_equal, equal}

///|
pub extend BundleToolError with Debug::{to_repr}

///|
pub extend BundleToolError with Show::{to_string, output}

///|
pub(all) suberror WindowsBundleError {
  InvalidRuntime(detail~ : String)
  InvalidLayout(detail~ : String)
} derive(Debug, Eq)

///|
pub extend WindowsBundleError with Eq::{not_equal, equal}

///|
pub extend WindowsBundleError with Debug::{to_repr}

///|
pub extend WindowsBundleError with Show::{to_string, output}

///|
pub(all) suberror LinuxBundleError {
  ToolFailure(stage~ : String, detail~ : String)
} derive(Debug, Eq)

///|
pub extend LinuxBundleError with Eq::{not_equal, equal}

///|
pub extend LinuxBundleError with Debug::{to_repr}

///|
pub extend LinuxBundleError with Show::{to_string, output}

///|
pub fn BundlePlanError::message(self : BundlePlanError) -> String {
  match self {
    UnsupportedResourceGlob(path~) =>
      "unsupported bundle resource glob: " + path
    MissingInput(path~) => "bundle input is missing: " + path
    NotLaunchableMachO(path~, filetype~) =>
      "bundle executable " +
      path +
      " is a Mach-O of type " +
      macho_filetype_name(filetype) +
      ", not MH_EXECUTE"
    InputOutsideBase(path~) => "bundle input must stay inside base_dir: " + path
  }
}

///|
pub fn BundleRuntimeError::message(self : BundleRuntimeError) -> String {
  match self {
    ExecutableMissing(path~) => "application executable is missing: " + path
    HelperMissing(path~) => "Proton helper executable is missing: " + path
  }
}

///|
pub fn BundleFileSystemError::message(self : BundleFileSystemError) -> String {
  match self {
    CreateDirectory(path~, detail~) =>
      "failed to create directory " + path + ": " + detail
    Copy(source~, destination~, detail~) =>
      "failed to copy " + source + " to " + destination + ": " + detail
    Read(path~, detail~) => "failed to read " + path + ": " + detail
    Write(path~, detail~) => "failed to write " + path + ": " + detail
  }
}

///|
pub fn BundleToolError::message(self : BundleToolError) -> String {
  match self {
    Exit(tool~, code~, detail~) =>
      tool + " exited with code " + code.to_string() + ": " + detail
  }
}

///|
pub fn WindowsBundleError::message(self : WindowsBundleError) -> String {
  match self {
    InvalidRuntime(detail~) => "invalid Windows Proton runtime: " + detail
    InvalidLayout(detail~) => "invalid Windows bundle layout: " + detail
  }
}

///|
pub fn LinuxBundleError::message(self : LinuxBundleError) -> String {
  match self {
    ToolFailure(stage~, detail~) => stage + " failed: " + detail
  }
}

///|
impl Show for BundlePlanError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for BundleRuntimeError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for BundleFileSystemError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for BundleToolError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for WindowsBundleError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for LinuxBundleError with fn output(self, logger) {
  logger.write_string(self.message())
}
