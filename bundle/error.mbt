///|
priv suberror BundlePlanError {
  UnsupportedResourceGlob(path~ : String)
  MissingInput(path~ : String)
  NotLaunchableMachO(path~ : String, filetype~ : Int)
  InputOutsideBase(path~ : String)
}

///|
priv suberror BundleRuntimeError {
  ExecutableMissing(path~ : String)
  HelperMissing(path~ : String)
  LegacyDynamicDependency(path~ : String, dependency~ : String)
}

///|
priv suberror BundleFileSystemError {
  CreateDirectory(path~ : String, detail~ : String)
  Copy(source~ : String, destination~ : String, detail~ : String)
  Read(path~ : String, detail~ : String)
  Write(path~ : String, detail~ : String)
}

///|
priv suberror BundleToolError {
  Exit(tool~ : String, code~ : Int, detail~ : String)
}

///|
priv suberror WindowsBundleError {
  InvalidRuntime(detail~ : String)
  InvalidLayout(detail~ : String)
}

///|
priv suberror LinuxBundleError {
  ToolFailure(stage~ : String, detail~ : String)
}

///|
fn BundlePlanError::message(self : BundlePlanError) -> String {
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
fn BundleRuntimeError::message(self : BundleRuntimeError) -> String {
  match self {
    ExecutableMissing(path~) => "application executable is missing: " + path
    HelperMissing(path~) => "Proton helper executable is missing: " + path
    LegacyDynamicDependency(path~, dependency~) =>
      "executable " +
      path +
      " still depends on removed Proton runtime library " +
      dependency
  }
}

///|
fn BundleFileSystemError::message(self : BundleFileSystemError) -> String {
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
fn BundleToolError::message(self : BundleToolError) -> String {
  match self {
    Exit(tool~, code~, detail~) =>
      tool + " exited with code " + code.to_string() + ": " + detail
  }
}

///|
fn WindowsBundleError::message(self : WindowsBundleError) -> String {
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
