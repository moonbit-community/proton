///|
priv suberror StagingPlanError {
  UnsupportedResourceGlob(path~ : String)
  MissingInput(path~ : String)
  NotLaunchableMachO(path~ : String, filetype~ : Int)
  InputOutsideBase(path~ : String)
}

///|
priv suberror StagingRuntimeError {
  ExecutableMissing(path~ : String)
  HelperMissing(path~ : String)
  UnsupportedPlatform(platform~ : String)
}

///|
priv suberror StagingFileSystemError {
  CreateDirectory(path~ : String, detail~ : String)
  Copy(source~ : String, destination~ : String, detail~ : String)
  Read(path~ : String, detail~ : String)
  Write(path~ : String, detail~ : String)
}

///|
priv suberror StagingToolError {
  Exit(tool~ : String, code~ : Int, detail~ : String)
}

///|
priv suberror WindowsStagingError {
  InvalidRuntime(detail~ : String)
  InvalidLayout(detail~ : String)
}

///|
priv suberror LinuxBundleError {
  ToolFailure(stage~ : String, detail~ : String)
}

///|
fn StagingPlanError::message(self : StagingPlanError) -> String {
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
fn StagingRuntimeError::message(self : StagingRuntimeError) -> String {
  match self {
    ExecutableMissing(path~) => "application executable is missing: " + path
    HelperMissing(path~) => "Proton helper executable is missing: " + path
    UnsupportedPlatform(platform~) =>
      "unsupported Proton package platform: " + platform
  }
}

///|
fn StagingFileSystemError::message(self : StagingFileSystemError) -> String {
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
fn StagingToolError::message(self : StagingToolError) -> String {
  match self {
    Exit(tool~, code~, detail~) =>
      tool + " exited with code " + code.to_string() + ": " + detail
  }
}

///|
fn WindowsStagingError::message(self : WindowsStagingError) -> String {
  match self {
    InvalidRuntime(detail~) => "invalid Windows Proton runtime: " + detail
    InvalidLayout(detail~) => "invalid Windows bundle layout: " + detail
  }
}

///|
fn LinuxBundleError::message(self : LinuxBundleError) -> String {
  match self {
    ToolFailure(stage~, detail~) => stage + " failed: " + detail
  }
}

///|
impl Show for StagingPlanError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for StagingRuntimeError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for StagingFileSystemError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for StagingToolError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for WindowsStagingError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for LinuxBundleError with fn output(self, logger) {
  logger.write_string(self.message())
}
