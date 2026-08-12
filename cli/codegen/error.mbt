///|
/// Schema failures in the `proton.ext.json` identity consumed by command codegen.
pub(all) suberror CodegenMetadataError {
  InvalidRoot
  UnknownField(field~ : String)
  MissingField(field~ : String)
  InvalidType(field~ : String, expected~ : String)
  InvalidPackageName(value~ : String, reason~ : String)
} derive(Debug, Eq)

///|
pub fn CodegenMetadataError::message(self : CodegenMetadataError) -> String {
  match self {
    InvalidRoot => "expected a JSON object for proton.ext.json"
    UnknownField(field~) => "unknown proton.ext.json field: " + field
    MissingField(field~) =>
      "proton.ext.json must contain string field `" + field + "`"
    InvalidType(field~, expected~) =>
      "proton.ext.json field `" + field + "` must be " + expected
    InvalidPackageName(value~, reason~) =>
      "invalid proton.ext.json package `" + value + "`: " + reason
  }
}

///|
impl Show for CodegenMetadataError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
/// Failures while locating or reading MoonBit sources for command codegen.
pub(all) suberror CodegenInputError {
  SourceParse(path~ : String)
  InputRead(path~ : String, detail~ : String)
  PackageRead(path~ : String, detail~ : String)
} derive(Debug, Eq)

///|
/// Failures while loading the `proton.ext.json` file associated with command codegen.
pub(all) suberror CodegenMetadataFileError {
  MissingMetadata(path~ : String)
  Syntax(path~ : String, diagnostics~ : String)
  Invalid(path~ : String, error~ : CodegenMetadataError)
} derive(Debug, Eq)

///|
/// Invalid typed command declarations.
pub(all) suberror CommandCodegenError {
  InvalidName(label~ : String, value~ : String, reason~ : String)
  Attribute(kind~ : String, detail~ : String)
  Command(function_name~ : String, detail~ : String)
  UnsupportedType(context~ : String)
  Duplicate(kind~ : String, name~ : String)
  MissingCommand
} derive(Debug, Eq)

///|
pub fn CodegenInputError::message(self : CodegenInputError) -> String {
  match self {
    SourceParse(path~) =>
      "failed to parse MoonBit source for #proton codegen: " + path
    InputRead(path~, detail~) => "failed to read " + path + ": " + detail
    PackageRead(path~, detail~) =>
      "failed to scan package " + path + ": " + detail
  }
}

///|
pub fn CodegenMetadataFileError::message(
  self : CodegenMetadataFileError,
) -> String {
  match self {
    MissingMetadata(path~) =>
      "missing proton.ext.json next to input file: " + path
    Syntax(path~, diagnostics~) => path + ": " + diagnostics
    Invalid(path~, error~) => path + ": " + error.message()
  }
}

///|
pub fn CommandCodegenError::message(self : CommandCodegenError) -> String {
  match self {
    InvalidName(label~, value~, reason~) => label + " `" + value + "` " + reason
    Attribute(kind~, detail~) => "#proton." + kind + ": " + detail
    Command(function_name~, detail~) =>
      "#proton.command " + function_name + ": " + detail
    UnsupportedType(context~) => "unsupported type: " + context
    Duplicate(kind~, name~) => "duplicate " + kind + ": " + name
    MissingCommand => "#proton.command codegen requires at least one command"
  }
}

///|
impl Show for CodegenInputError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for CodegenMetadataFileError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for CommandCodegenError with fn output(self, logger) {
  logger.write_string(self.message())
}
