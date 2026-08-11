///|
priv suberror DoctorRuntimeManifestError {
  Invalid(String)
} derive(Debug)

///|
pub(all) suberror DoctorError {
  WorkingDirectoryMissing(path~ : String)
  WorkingDirectoryNotDirectory(path~ : String)
  OutputWrite(path~ : String, detail~ : String)
} derive(Debug, Eq)

///|
fn DoctorRuntimeManifestError::message(
  self : DoctorRuntimeManifestError,
) -> String {
  match self {
    Invalid(message) => message
  }
}

///|
impl Show for DoctorRuntimeManifestError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub fn DoctorError::message(self : DoctorError) -> String {
  match self {
    WorkingDirectoryMissing(path~) => "cwd does not exist: " + path
    WorkingDirectoryNotDirectory(path~) => "cwd is not a directory: " + path
    OutputWrite(path~, detail~) =>
      "failed to write doctor output " + path + ": " + detail
  }
}

///|
impl Show for DoctorError with fn output(self, logger) {
  logger.write_string(self.message())
}
