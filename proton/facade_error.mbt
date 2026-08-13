///|
pub fn AppConfigurationError::message(self : AppConfigurationError) -> String {
  match self {
    InvalidSetting(name~, message~) => name + ": " + message
    Bootstrap(error) => error.message()
    ExtensionDependencyCycle(extension_id~) =>
      "command extension dependency cycle detected at: " + extension_id
    ExtensionUnavailable(extension_id~, requested_by~, state~) =>
      match requested_by {
        Some(parent) =>
          "command extension " +
          parent +
          " requires " +
          state +
          " dependency " +
          extension_id
        None => "enabled command extension is " + state + ": " + extension_id
      }
    ExtensionAdaptationFailed(extension_id~, error~) =>
      "failed to adapt extension " + extension_id + ": " + error.message()
    InvalidJavaScriptNamespace(js_namespace~) =>
      "command extension namespace cannot be exposed to JavaScript: " +
      js_namespace
    InvalidJavaScriptApi(js_namespace~, api_name~) =>
      "command extension API cannot be exposed to JavaScript: " +
      js_namespace +
      "." +
      api_name
    InvalidEntryUrl(url~, reason~) => "invalid entry URL " + url + ": " + reason
    InvalidPermissionGrant(detail~) => "invalid permission grant: " + detail
    MissingPermissionGrant(extension_id~) =>
      "registered renderer capability has no permission grant: " + extension_id
  }
}

///|
impl Show for AppConfigurationError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub fn AppEntryError::message(self : AppEntryError) -> String {
  match self {
    ReadFailed(path~, detail~) =>
      "failed to read HTML entry " + path + ": " + detail
    NativeLoad(action~, error~) => action + " failed: " + error.message()
    ClosedDuringStartup => "window closed before startup completed"
  }
}

///|
impl Show for AppEntryError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub fn CommandExtensionLifecycleError::message(
  self : CommandExtensionLifecycleError,
) -> String {
  match self {
    ApplicationRegistrationFailed(detail~) =>
      "failed to register application commands: " + detail
    RegistrationFailed(extension_id~, detail~) =>
      "failed to register command extension " + extension_id + ": " + detail
    DestroyFailed(extension_id~, detail~) =>
      "failed to destroy command extension " + extension_id + ": " + detail
  }
}

///|
impl Show for CommandExtensionLifecycleError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub fn LifecycleHookError::message(self : LifecycleHookError) -> String {
  match self {
    ApplicationStart(index~, detail~) =>
      "application startup hook " + index.to_string() + " failed: " + detail
    ApplicationShutdown(index~, detail~) =>
      "application shutdown hook " + index.to_string() + " failed: " + detail
    WindowReady(index~, detail~) =>
      "window ready hook " + index.to_string() + " failed: " + detail
    WindowClose(index~, detail~) =>
      "window close hook " + index.to_string() + " failed: " + detail
  }
}

///|
impl Show for LifecycleHookError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub fn AppCleanupError::message(self : AppCleanupError) -> String {
  match self {
    CommandExtension(error) => error.message()
    LifecycleHook(error) => error.message()
    WindowDestroy(error) => "failed to destroy window: " + error.message()
    RuntimeDestroy(error) => "failed to destroy runtime: " + error.message()
  }
}

///|
impl Show for AppCleanupError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub fn WindowSessionError::message(self : WindowSessionError) -> String {
  match self {
    UnknownWindow(id~) => "window is not declared: " + id
    AlreadyOpen(id~) => "window is already open: " + id
    StaleWindow(id~) => "window instance is no longer active: " + id
    UnknownView(id~) => "view does not exist in its window: " + id
    AlreadyExists(id~) => "view already exists in its window: " + id
    StaleView(id~) => "view instance is no longer active: " + id
    Cancelled => "window operation was cancelled"
    OperationFailed(action~, error~) => action + " failed: " + error.message()
    StartupFailed(id~, error~) =>
      "failed to open window " + id + ": " + error.message()
  }
}

///|
impl Show for WindowSessionError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
fn cleanup_failure_message(
  primary : String?,
  failures : Array[AppCleanupError],
) -> String {
  let builder = StringBuilder::new()
  match primary {
    Some(message) => {
      builder.write_string(message)
      builder.write_string("\n")
    }
    None => ()
  }
  builder.write_string("application teardown failed")
  for failure in failures {
    builder.write_string("\n- ")
    builder.write_string(failure.message())
  }
  builder.to_string()
}

///|
pub fn AppRunError::message(self : AppRunError) -> String {
  match self {
    EventLoopError(message) => "application event loop failed: " + message
    ConfigurationError(error) =>
      "application configuration failed: " + error.message()
    UnsupportedNativeFeature(feature~) =>
      "the active Proton native runtime does not support required feature: " +
      feature
    NativeRuntimeError(action~, error~) =>
      "native runtime failed during " + action + ": " + error.message()
    CommandExtensionLifecycleError(error) =>
      "command extension lifecycle failed: " + error.message()
    LifecycleHookError(error) =>
      "application lifecycle failed: " + error.message()
    EntryLoadError(error) =>
      "application entry failed to load: " + error.message()
    BridgeStartupError(diagnostic) =>
      "application startup failed [" +
      diagnostic.code +
      "]: " +
      diagnostic.message +
      "\n" +
      @debug.render(Repr(diagnostic))
    BridgeRuntimeError(diagnostic) =>
      "application bridge failed [" +
      diagnostic.code +
      "]: " +
      diagnostic.message +
      "\n" +
      @debug.render(Repr(diagnostic))
    CleanupFailed(primary~, failures~) =>
      cleanup_failure_message(primary, failures)
    UnexpectedTaskFailure(detail~) => "application task failed: " + detail
  }
}

///|
impl Show for AppRunError with fn output(self, logger) {
  logger.write_string(self.message())
}
