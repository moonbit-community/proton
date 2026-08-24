///|
priv suberror CefPlatformError {
  Unsupported(platform~ : String)
}

///|
priv suberror CefFileSystemError {
  CreateDirectory(path~ : String, detail~ : String)
  ReadDirectory(path~ : String, detail~ : String)
  Copy(source~ : String, destination~ : String, detail~ : String)
  Write(path~ : String, detail~ : String)
  Remove(path~ : String, detail~ : String)
  InvalidSource(path~ : String)
}

///|
priv suberror CefDownloadError {
  CreateTemporaryDirectory(detail~ : String)
  Start(url~ : String, detail~ : String)
  CurlExit(url~ : String, code~ : Int)
  OpenArchive(path~ : String, detail~ : String)
  ChecksumMismatch(expected~ : String, actual~ : String)
  ExtractStart(path~ : String, detail~ : String)
  ExtractExit(path~ : String, code~ : Int)
  ExtractedRootNotFound(path~ : String)
}

///|
priv suberror CefRuntimeError {
  StoreRootUnavailable
  StoreRootNotAbsolute(path~ : String)
  NotInstalled(path~ : String)
  InvalidCefRoot(path~ : String, missing~ : Array[String])
  InvalidRuntime(path~ : String, missing~ : Array[String])
  ManifestRead(path~ : String, detail~ : String)
  ManifestSyntax(path~ : String, detail~ : String)
  ManifestInvalid(path~ : String, detail~ : String)
  RequirementRead(path~ : String, detail~ : String)
  RequirementSyntax(path~ : String, detail~ : String)
  RequirementInvalid(path~ : String, detail~ : String)
}

///|
fn CefPlatformError::message(self : CefPlatformError) -> String {
  match self {
    Unsupported(platform~) =>
      "The Proton CEF backend is not supported for " + platform + "."
  }
}

///|
fn CefFileSystemError::message(self : CefFileSystemError) -> String {
  match self {
    CreateDirectory(path~, detail~) =>
      "Failed to create directory " + path + ": " + detail
    ReadDirectory(path~, detail~) =>
      "Failed to read directory " + path + ": " + detail
    Copy(source~, destination~, detail~) =>
      "Failed to copy " + source + " to " + destination + ": " + detail
    Write(path~, detail~) => "Failed to write " + path + ": " + detail
    Remove(path~, detail~) => "Failed to remove " + path + ": " + detail
    InvalidSource(path~) => "Source path is not a file or directory: " + path
  }
}

///|
fn CefDownloadError::message(self : CefDownloadError) -> String {
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
fn CefRuntimeError::message(self : CefRuntimeError) -> String {
  match self {
    StoreRootUnavailable =>
      "Cannot resolve the Proton runtime store because no home directory is available"
    StoreRootNotAbsolute(path~) =>
      "PROTON_RUNTIME_STORE must be an absolute path: " + path
    NotInstalled(path~) =>
      "The required Proton runtime is not installed: " + path
    InvalidCefRoot(path~, missing~) =>
      "Invalid CEF root: " + path + "\nMissing:\n" + missing.join("\n")
    InvalidRuntime(path~, missing~) =>
      "Invalid Proton runtime: " + path + "\nMissing:\n" + missing.join("\n")
    ManifestRead(path~, detail~) =>
      "Failed to read manifest " + path + ": " + detail
    ManifestSyntax(path~, detail~) =>
      "Invalid JSON in manifest " + path + ": " + detail
    ManifestInvalid(path~, detail~) =>
      "Invalid manifest " + path + ": " + detail
    RequirementRead(path~, detail~) =>
      "Failed to read CEF requirements " + path + ": " + detail
    RequirementSyntax(path~, detail~) =>
      "Invalid JSON in CEF requirements " + path + ": " + detail
    RequirementInvalid(path~, detail~) =>
      "Invalid CEF requirements " + path + ": " + detail
  }
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
