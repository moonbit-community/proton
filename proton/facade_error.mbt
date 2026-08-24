///|
fn window_operation_failed(
  action : String,
  error : @native.NativeError,
) -> WindowSessionError {
  OperationFailed(action~, status=error.status(), detail=error.message())
}

///|
fn runtime_operation_failed(
  action : String,
  error : @native.NativeError,
) -> AppRunError {
  RuntimeOperationFailed(action~, status=error.status(), detail=error.message())
}

///|
fn entry_platform_load_failed(
  action : String,
  error : @native.NativeError,
) -> AppEntryError {
  PlatformLoad(action~, status=error.status(), detail=error.message())
}

///|
pub fn AppConfigurationError::message(self : AppConfigurationError) -> String {
  match self {
    InvalidSetting(name~, message~) => name + ": " + message
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
    InvalidRendererCapability(detail~) =>
      "invalid renderer capability: " + detail
  }
}

///|
impl Show for AppConfigurationError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub extend AppConfigurationError with Show::{to_string, output}

///|
pub fn AppEntryError::message(self : AppEntryError) -> String {
  match self {
    ReadFailed(path~, detail~) =>
      "failed to read HTML entry " + path + ": " + detail
    PlatformLoad(action~, status~, detail~) =>
      action + " failed (" + status.to_string() + "): " + detail
    ClosedDuringStartup => "window closed before startup completed"
  }
}

///|
impl Show for AppEntryError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub extend AppEntryError with Show::{to_string, output}

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
pub extend CommandExtensionLifecycleError with Show::{to_string, output}

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
pub extend LifecycleHookError with Show::{to_string, output}

///|
pub fn AppCleanupError::message(self : AppCleanupError) -> String {
  match self {
    CommandExtension(error) => error.message()
    LifecycleHook(error) => error.message()
    WindowDestroy(status~, detail~) =>
      "failed to destroy window (" + status.to_string() + "): " + detail
    RuntimeDestroy(status~, detail~) =>
      "failed to destroy runtime (" + status.to_string() + "): " + detail
  }
}

///|
impl Show for AppCleanupError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub extend AppCleanupError with Show::{to_string, output}

///|
pub fn WindowSessionError::message(self : WindowSessionError) -> String {
  match self {
    UnknownWindow(id~) => "window is not declared: " + id
    AlreadyOpen(id~) => "window is already open: " + id
    ApplicationQuitting => "the application is quitting"
    StaleWindow(id~) => "window instance is no longer active: " + id
    UnknownView(id~) => "view does not exist in its window: " + id
    AlreadyExists(id~) => "view already exists in its window: " + id
    StaleView(id~) => "view instance is no longer active: " + id
    Cancelled => "window operation was cancelled"
    OperationFailed(action~, status~, detail~) =>
      action + " failed (" + status.to_string() + "): " + detail
    StartupFailed(id~, error~) =>
      "failed to open window " + id + ": " + error.message()
  }
}

///|
impl Show for WindowSessionError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub extend WindowSessionError with Show::{to_string, output}

///|
pub fn ScreenQueryError::message(self : ScreenQueryError) -> String {
  match self {
    QueryFailed(status~, detail~) =>
      "failed to query screens (" + status.to_string() + "): " + detail
  }
}

///|
impl Show for ScreenQueryError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub extend ScreenQueryError with Show::{to_string, output}

///|
fn cleanup_failure_message(
  primary : String?,
  failures : Array[AppCleanupError],
) -> String {
  let builder = StringBuilder()
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
    RuntimeOperationFailed(action~, status~, detail~) =>
      "runtime failed during " +
      action +
      " (" +
      status.to_string() +
      "): " +
      detail
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

///|
pub extend AppRunError with Show::{to_string, output}
