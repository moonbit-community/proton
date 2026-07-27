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
    InvalidDevelopmentUrl(url~, reason~) =>
      "invalid development bridge URL " + url + ": " + reason
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
pub fn RuntimeWakeupError::message(self : RuntimeWakeupError) -> String {
  match self {
    UnsupportedFeature(feature~) =>
      "the native runtime does not provide the required wakeup feature: " +
      feature
    PipeCreateFailed(detail~) =>
      "failed to create the runtime wakeup pipe: " + detail
    SourceOpenFailed(source~, detail~) =>
      "failed to open runtime wakeup source " + source + ": " + detail
    SourceClosed => "runtime wakeup source closed unexpectedly"
    MissingNotification =>
      "runtime wakeup wait completed without a notification"
  }
}

///|
impl Show for RuntimeWakeupError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub fn CommandExtensionLifecycleError::message(
  self : CommandExtensionLifecycleError,
) -> String {
  match self {
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
pub fn AppRunError::message(self : AppRunError) -> String {
  match self {
    RunnerError(message) => "application runner is not active: " + message
    ConfigurationError(error) =>
      "application configuration failed: " + error.message()
    NativeRuntimeError(action~, error~) =>
      "native runtime failed during " + action + ": " + error.message()
    RuntimeWakeupError(error) => "runtime wakeup failed: " + error.message()
    CommandExtensionLifecycleError(error) =>
      "command extension lifecycle failed: " + error.message()
    EntryLoadError(error) =>
      "application entry failed to load: " + error.message()
    BridgeStartupError(diagnostic) =>
      "application startup failed [" +
      diagnostic.code +
      "]: " +
      diagnostic.message +
      "\n" +
      @debug.render(@debug.to_repr(diagnostic))
    BridgeRuntimeError(diagnostic) =>
      "application bridge failed [" +
      diagnostic.code +
      "]: " +
      diagnostic.message +
      "\n" +
      @debug.render(@debug.to_repr(diagnostic))
    UnexpectedTaskFailure(detail~) => "application task failed: " + detail
  }
}

///|
impl Show for AppRunError with fn output(self, logger) {
  logger.write_string(self.message())
}
