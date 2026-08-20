///|
pub(all) suberror DoctorError {
  WorkingDirectoryMissing(path~ : String)
  WorkingDirectoryNotDirectory(path~ : String)
  OutputWrite(path~ : String, detail~ : String)
} derive(Debug, Eq)

///|
pub extend DoctorError with Eq::{not_equal, equal}

///|
pub extend DoctorError with Debug::{to_repr}

///|
pub extend DoctorError with Show::{to_string, output}

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
