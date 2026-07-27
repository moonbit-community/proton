///|
/// Schema failures in the `moon.ext` identity consumed by command codegen.
pub(all) suberror CodegenMetadataError {
  InvalidRoot
  DuplicateField(field~ : String)
  UnknownField(field~ : String)
  MissingField(field~ : String)
  InvalidType(field~ : String, expected~ : String)
  InvalidPackageName(value~ : String, reason~ : String)
} derive(Debug, Eq)

///|
pub fn CodegenMetadataError::message(self : CodegenMetadataError) -> String {
  match self {
    InvalidRoot => "expected field list for moon.ext"
    DuplicateField(field~) => "duplicate moon.ext field: " + field
    UnknownField(field~) => "unknown moon.ext field: " + field
    MissingField(field~) => "moon.ext must contain string field `" + field + "`"
    InvalidType(field~, expected~) =>
      "moon.ext field `" + field + "` must be " + expected
    InvalidPackageName(value~, reason~) =>
      "invalid moon.ext package `" + value + "`: " + reason
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
/// Failures while loading the `moon.ext` file associated with command codegen.
pub(all) suberror CodegenMetadataFileError {
  MissingMetadata(path~ : String)
  Syntax(path~ : String, diagnostics~ : String)
  Invalid(path~ : String, error~ : CodegenMetadataError)
} derive(Debug, Eq)

///|
/// Invalid command, script, destroy hook, and event declarations.
pub(all) suberror CommandCodegenError {
  InvalidName(label~ : String, value~ : String, reason~ : String)
  Attribute(kind~ : String, detail~ : String)
  Command(function_name~ : String, detail~ : String)
  Script(function_name~ : String, detail~ : String)
  Destroy(function_name~ : String, detail~ : String)
  Event(type_name~ : String, detail~ : String)
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
    MissingMetadata(path~) => "missing moon.ext next to input file: " + path
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
    Script(function_name~, detail~) =>
      "#proton.script " + function_name + ": " + detail
    Destroy(function_name~, detail~) =>
      "#proton.destroy " + function_name + ": " + detail
    Event(type_name~, detail~) => "#proton.event " + type_name + ": " + detail
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
