///|
priv suberror MoonConfigReadError {
  MissingFile(String)
  ReadFailed(String, String)
  ParseFailed(String, String)
} derive(Debug)

///|
priv suberror DoctorRuntimeManifestError {
  Read(path~ : String)
  Syntax(path~ : String)
  UnknownField(path~ : String, field~ : String)
  MissingField(path~ : String, field~ : String)
  InvalidSchema(path~ : String)
  InvalidRoot(path~ : String)
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
    Read(path~) => "failed to read Proton runtime manifest: " + path
    Syntax(path~) => "failed to parse Proton runtime manifest: " + path
    UnknownField(path~, field~) =>
      "Proton runtime manifest has unknown field `" + field + "`: " + path
    MissingField(path~, field~) =>
      "Proton runtime manifest has no `" + field + "`: " + path
    InvalidSchema(path~) =>
      "Proton runtime manifest schema_version must be 1: " + path
    InvalidRoot(path~) =>
      "Proton runtime manifest must be a JSON object: " + path
  }
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

///|
impl Show for DoctorRuntimeManifestError with fn output(self, logger) {
  logger.write_string(self.message())
}
