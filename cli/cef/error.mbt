///|
pub(all) suberror CefUsageError {
  InvalidArchiveName(name~ : String)
  InvalidChecksum(value~ : String)
  MissingCustomChecksum
} derive(Debug, Eq)

///|
pub(all) suberror CefPlatformError {
  Unsupported(platform~ : String)
} derive(Debug, Eq)

///|
pub(all) suberror CefFileSystemError {
  CurrentDirectoryUnavailable
  CreateDirectory(path~ : String, detail~ : String)
  ReadDirectory(path~ : String, detail~ : String)
  Copy(source~ : String, destination~ : String, detail~ : String)
  Write(path~ : String, detail~ : String)
  Remove(path~ : String, detail~ : String)
  MakeExecutable(path~ : String, detail~ : String)
  InvalidSource(path~ : String)
} derive(Debug, Eq)

///|
pub(all) suberror CefDownloadError {
  CreateTemporaryDirectory(detail~ : String)
  Start(url~ : String, detail~ : String)
  CurlExit(url~ : String, code~ : Int)
  OpenArchive(path~ : String, detail~ : String)
  ChecksumMismatch(expected~ : String, actual~ : String)
  ExtractStart(path~ : String, detail~ : String)
  ExtractExit(path~ : String, code~ : Int)
  ExtractedRootNotFound(path~ : String)
} derive(Debug, Eq)

///|
pub(all) suberror CefRuntimeError {
  InvalidCefRoot(path~ : String, missing~ : Array[String])
  InvalidRuntime(path~ : String, missing~ : Array[String])
  PrebuiltNotFound(platform~ : String)
  ManifestRead(path~ : String, detail~ : String)
  ManifestSyntax(path~ : String, detail~ : String)
  ManifestShape(path~ : String, detail~ : String)
  ManifestField(path~ : String, field~ : String)
  PrebuiltVersionMismatch(expected~ : String, actual~ : String)
  ActivePlatformMismatch(expected~ : String, actual~ : String)
  ActiveVersionMismatch(expected~ : String, actual~ : String)
  ActiveDistMismatch(expected~ : String, actual~ : String)
  UnsafeGeneratedDirectory(path~ : String)
  UnsafeInstallDirectory(path~ : String)
  RuntimeConflict(path~ : String, detail~ : String)
} derive(Debug, Eq)

///|
pub fn CefUsageError::message(self : CefUsageError) -> String {
  match self {
    InvalidArchiveName(name~) => "Invalid CEF archive name: " + name
    InvalidChecksum(value~) => "Invalid CEF archive SHA-256: " + value
    MissingCustomChecksum => "Custom CEF archive name or URL requires --sha256"
  }
}

///|
pub fn CefPlatformError::message(self : CefPlatformError) -> String {
  match self {
    Unsupported(platform~) =>
      "The Proton CEF backend is not supported for " + platform + "."
  }
}

///|
pub fn CefFileSystemError::message(self : CefFileSystemError) -> String {
  match self {
    CurrentDirectoryUnavailable => "Failed to read current directory"
    CreateDirectory(path~, detail~) =>
      "Failed to create directory " + path + ": " + detail
    ReadDirectory(path~, detail~) =>
      "Failed to read directory " + path + ": " + detail
    Copy(source~, destination~, detail~) =>
      "Failed to copy " + source + " to " + destination + ": " + detail
    Write(path~, detail~) => "Failed to write " + path + ": " + detail
    Remove(path~, detail~) => "Failed to remove " + path + ": " + detail
    MakeExecutable(path~, detail~) =>
      "Failed to make executable " + path + ": " + detail
    InvalidSource(path~) => "Source path is not a file or directory: " + path
  }
}

///|
pub fn CefDownloadError::message(self : CefDownloadError) -> String {
  match self {
    CreateTemporaryDirectory(detail~) =>
      "Failed to create temp directory: " + detail
    Start(url~, detail~) => "Download failed for " + url + ": " + detail
    CurlExit(url~, code~) =>
      "Download failed for " +
      url +
      ": curl exited with code " +
      code.to_string()
    OpenArchive(path~, detail~) =>
      "Failed to open downloaded CEF archive " + path + ": " + detail
    ChecksumMismatch(expected~, actual~) =>
      "CEF archive SHA-256 mismatch: expected " + expected + ", got " + actual
    ExtractStart(path~, detail~) => "tar failed for " + path + ": " + detail
    ExtractExit(path~, code~) =>
      "tar failed for " + path + " with exit code " + code.to_string()
    ExtractedRootNotFound(path~) =>
      "Could not find extracted CEF root in " + path
  }
}

///|
pub fn CefRuntimeError::message(self : CefRuntimeError) -> String {
  match self {
    InvalidCefRoot(path~, missing~) =>
      "Invalid CEF root: " + path + "\nMissing:\n" + missing.join("\n")
    InvalidRuntime(path~, missing~) =>
      "Invalid Proton runtime: " + path + "\nMissing:\n" + missing.join("\n")
    PrebuiltNotFound(platform~) =>
      "Could not find Proton prebuilt artifacts for " + platform
    ManifestRead(path~, detail~) =>
      "Failed to read manifest " + path + ": " + detail
    ManifestSyntax(path~, detail~) =>
      "Invalid JSON in manifest " + path + ": " + detail
    ManifestShape(path~, detail~) => "Invalid manifest " + path + ": " + detail
    ManifestField(path~, field~) =>
      "Manifest " + path + " missing string field: " + field
    PrebuiltVersionMismatch(expected~, actual~) =>
      "Proton prebuilt version mismatch: expected " +
      expected +
      ", got " +
      actual
    ActivePlatformMismatch(expected~, actual~) =>
      "Active runtime platform mismatch: expected " +
      expected +
      ", got " +
      actual
    ActiveVersionMismatch(expected~, actual~) =>
      "Active runtime Proton version mismatch: expected " +
      expected +
      ", got " +
      actual
    ActiveDistMismatch(expected~, actual~) =>
      "Active runtime dist mismatch: expected " + expected + ", got " + actual
    UnsafeGeneratedDirectory(path~) =>
      "Refusing to replace unsafe generated directory: " + path
    UnsafeInstallDirectory(path~) =>
      "Refusing to replace unsafe CEF install directory: " + path
    RuntimeConflict(path~, detail~) =>
      "Cannot assemble Proton runtime at " + path + ": " + detail
  }
}

///|
impl Show for CefUsageError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for CefPlatformError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for CefFileSystemError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for CefDownloadError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for CefRuntimeError with fn output(self, logger) {
  logger.write_string(self.message())
}
