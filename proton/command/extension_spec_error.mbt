///|
/// Invalid typed metadata supplied while constructing an extension spec.
pub(all) suberror ExtensionSpecError {
  InvalidContract(detail~ : String)
  ForeignCommandRoute(extension_id~ : String, operation_name~ : String)
} derive(Eq)

///|
pub extend ExtensionSpecError with Eq::{not_equal, equal}

///|
pub extend ExtensionSpecError with Show::{to_string, output}

///|
/// A stable validation failure for an extension's renderer permission scope.
pub(all) suberror PermissionScopeValidationError {
  Invalid(detail~ : String)
} derive(Eq)

///|
pub extend PermissionScopeValidationError with Eq::{not_equal, equal}

///|
pub extend PermissionScopeValidationError with Show::{to_string, output}

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
pub fn PermissionScopeValidationError::message(
  self : PermissionScopeValidationError,
) -> String {
  match self {
    Invalid(detail~) => detail
  }
}

///|
impl Show for ExtensionSpecError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for PermissionScopeValidationError with fn output(self, logger) {
  logger.write_string(self.message())
}
