///|
/// Invalid typed metadata supplied while constructing an extension spec.
pub(all) suberror ExtensionSpecError {
  InvalidContract(detail~ : String)
  ForeignCommandRoute(extension_id~ : String, operation_name~ : String)
} derive(Eq)

///|
pub fn ExtensionSpecError::message(self : ExtensionSpecError) -> String {
  match self {
    InvalidContract(detail~) => "invalid extension contract: " + detail
    ForeignCommandRoute(extension_id~, operation_name~) =>
      "command route " +
      operation_name +
      " does not belong to extension " +
      extension_id
  }
}

///|
impl Show for ExtensionSpecError with fn output(self, logger) {
  logger.write_string(self.message())
}
