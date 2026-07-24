///|
/// Failures while adding command handlers to an operation registry.
pub(all) suberror OpRegistrationError {
  EmptyName
  DuplicateName(name~ : String)
  HostClosed
  RegistrationSealed
} derive(Debug, Eq)

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
/// Invalid extension identities, API names, and event targets.
pub(all) suberror ExtensionHostError {
  EmptyExtensionId
  EmptyNamespace
  ReservedNamespace(extension_namespace~ : String)
  DuplicateExtensionId(id~ : String)
  DuplicateNamespace(extension_namespace~ : String)
  EmptyApiName(extension_namespace~ : String)
  ReservedApiName(extension_namespace~ : String, api_name~ : String)
  DuplicateApi(extension_namespace~ : String, api_name~ : String)
  NamespaceNotInstalled(extension_namespace~ : String)
  EmptyEventNamespace
  EmptyEventName(extension_namespace~ : String)
} derive(Debug, Eq)

///|
pub fn ExtensionHostError::message(self : ExtensionHostError) -> String {
  match self {
    EmptyExtensionId => "extension id must not be empty"
    EmptyNamespace => "extension namespace must not be empty"
    ReservedNamespace(extension_namespace~) =>
      "reserved extension namespace: " + extension_namespace
    DuplicateExtensionId(id~) => "extension already installed: " + id
    DuplicateNamespace(extension_namespace~) =>
      "extension namespace already installed: " + extension_namespace
    EmptyApiName(extension_namespace~) =>
      "extension API name must not be empty: " + extension_namespace
    ReservedApiName(extension_namespace~, api_name~) =>
      "reserved extension API name: " + extension_namespace + "." + api_name
    DuplicateApi(extension_namespace~, api_name~) =>
      "extension API already registered: " +
      extension_namespace +
      "." +
      api_name
    NamespaceNotInstalled(extension_namespace~) =>
      "extension namespace is not installed: " + extension_namespace
    EmptyEventNamespace => "extension event namespace must not be empty"
    EmptyEventName(extension_namespace~) =>
      "extension event name must not be empty: " + extension_namespace
  }
}

///|
impl Show for ExtensionHostError with fn output(self, logger) {
  logger.write_string(self.message())
}
