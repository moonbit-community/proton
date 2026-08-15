///|
/// Failures while adding command handlers to an operation registry.
pub(all) suberror OpRegistrationError {
  EmptyName
  DuplicateName(name~ : String)
  HostClosed
  RegistrationSealed
} derive(Debug, Eq)

///|
pub extend OpRegistrationError with Eq::{not_equal, equal}

///|
pub extend OpRegistrationError with Debug::{to_repr}

///|
pub extend OpRegistrationError with Show::{to_string, output}

///|
pub fn OpRegistrationError::message(self : OpRegistrationError) -> String {
  match self {
    EmptyName => "op name must not be empty"
    DuplicateName(name~) => "op already registered: " + name
    HostClosed => "cannot register op after host close"
    RegistrationSealed => "cannot register op after registration is sealed"
  }
}

///|
impl Show for OpRegistrationError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
/// Failures while decoding and invoking one registered operation.
pub(all) suberror OpDispatchError {
  InvalidPayload(name~ : String, detail~ : String)
  UnknownOp(name~ : String)
  HandlerFailed(name~ : String, detail~ : String)
  HostClosed
  AsyncHandlerRequiresAsync(name~ : String)
} derive(Debug, Eq)

///|
pub extend OpDispatchError with Eq::{not_equal, equal}

///|
pub extend OpDispatchError with Debug::{to_repr}

///|
pub extend OpDispatchError with Show::{to_string, output}

///|
pub fn OpDispatchError::message(self : OpDispatchError) -> String {
  match self {
    InvalidPayload(name~, detail~) =>
      "invalid payload for op " + name + ": " + detail
    UnknownOp(name~) => "Unknown op: " + name
    HandlerFailed(name~, detail~) => "op " + name + " failed: " + detail
    HostClosed => "MBT process host is closed"
    AsyncHandlerRequiresAsync(name~) =>
      "async op " + name + " requires dispatch_async()"
  }
}

///|
impl Show for OpDispatchError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
/// A command attempted to use a capability outside its request grant.
pub(all) suberror CommandPermissionError {
  Missing(extension_id~ : String)
  Foreign(expected~ : String, actual~ : String)
} derive(Debug, Eq)

///|
pub extend CommandPermissionError with Eq::{not_equal, equal}

///|
pub extend CommandPermissionError with Debug::{to_repr}

///|
pub fn CommandPermissionError::message(self : CommandPermissionError) -> String {
  match self {
    Missing(extension_id~) =>
      "request has no permission for extension " + extension_id
    Foreign(expected~, actual~) =>
      "request permission belongs to " + actual + ", not " + expected
  }
}
