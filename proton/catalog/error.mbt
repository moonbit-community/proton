///|
/// Schema and semantic failures inside one parsed `proton.ext.json` document.
pub(all) suberror ExtensionMetadataError {
  UnknownField(field~ : String)
  MissingField(field~ : String)
  InvalidType(field~ : String, expected~ : String)
  EmptyField(field~ : String)
  UnsupportedPlatform(platform~ : String)
  DuplicateValue(field~ : String, value~ : String)
  SelfDependency(id~ : String)
  InvalidNamespace(value~ : String, reason~ : String)
  InvalidImportPath(value~ : String, reason~ : String)
  InvalidPackageName(value~ : String, reason~ : String)
} derive(Debug, Eq)

///|
pub fn ExtensionMetadataError::message(self : ExtensionMetadataError) -> String {
  match self {
    UnknownField(field~) => "unknown proton.ext.json field: " + field
    MissingField(field~) => "missing required proton.ext.json field: " + field
    InvalidType(field~, expected~) =>
      "proton.ext.json field `" + field + "` must be " + expected
    EmptyField(field~) =>
      "proton.ext.json field `" + field + "` must not be empty"
    UnsupportedPlatform(platform~) =>
      "proton.ext.json platforms contains unsupported platform: " + platform
    DuplicateValue(field~, value~) =>
      "proton.ext.json " + field + " contains duplicate value: " + value
    SelfDependency(id~) =>
      "proton.ext.json dependencies must not include itself: " + id
    InvalidNamespace(value~, reason~) =>
      "invalid proton.ext.json namespace `" + value + "`: " + reason
    InvalidImportPath(value~, reason~) =>
      "invalid MoonBit import path `" + value + "`: " + reason
    InvalidPackageName(value~, reason~) =>
      "invalid proton.ext.json package `" + value + "`: " + reason
  }
}

///|
impl Show for ExtensionMetadataError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
/// Failures while locating, reading, or decoding one extension descriptor.
pub(all) suberror ExtensionDescriptorError {
  InvalidMetadataFile(path~ : String)
  ReadFailed(path~ : String, detail~ : String)
  Syntax(path~ : String, diagnostics~ : String)
  InvalidRoot(path~ : String)
  InvalidMetadata(path~ : String, error~ : ExtensionMetadataError)
} derive(Debug, Eq)

///|
pub fn ExtensionDescriptorError::message(
  self : ExtensionDescriptorError,
) -> String {
  match self {
    InvalidMetadataFile(path~) =>
      path + ": extension metadata must be proton.ext.json"
    ReadFailed(path~, detail~) =>
      path + ": failed to read metadata file: " + detail
    Syntax(path~, diagnostics~) => path + ": " + diagnostics
    InvalidRoot(path~) => path + ": expected a JSON object for proton.ext.json"
    InvalidMetadata(path~, error~) => path + ": " + error.message()
  }
}

///|
impl Show for ExtensionDescriptorError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
/// Failures while discovering and assembling an extension catalog.
pub(all) suberror ExtensionCatalogError {
  Descriptor(ExtensionDescriptorError)
  EmptyDescriptorId(path~ : String)
  DuplicateExtensionId(id~ : String, path~ : String)
  UnknownExtensionId(id~ : String)
  SearchRootMissing(path~ : String)
  SearchRootInspectFailed(path~ : String, detail~ : String)
  InvalidSearchRoot(path~ : String)
  DirectoryReadFailed(path~ : String, detail~ : String)
} derive(Debug, Eq)

///|
pub fn ExtensionCatalogError::message(self : ExtensionCatalogError) -> String {
  match self {
    Descriptor(error) => error.message()
    EmptyDescriptorId(path~) => path + ": extension id must not be empty"
    DuplicateExtensionId(id~, path~) => path + ": duplicate extension id: " + id
    UnknownExtensionId(id~) => id + ": unknown extension id: " + id
    SearchRootMissing(path~) =>
      path + ": extension search root does not exist: " + path
    SearchRootInspectFailed(path~, detail~) =>
      path + ": failed to inspect extension search root: " + detail
    InvalidSearchRoot(path~) =>
      path +
      ": extension search root must be a directory or extension metadata file"
    DirectoryReadFailed(path~, detail~) =>
      path + ": failed to read extension search root: " + detail
  }
}

///|
impl Show for ExtensionCatalogError with fn output(self, logger) {
  logger.write_string(self.message())
}
