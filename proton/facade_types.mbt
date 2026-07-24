///|
/// High-level application facade for ordinary Proton apps.
struct App {
  file_path : String?
  auto_config : Bool
  mut window : @manifest.WindowManifest
  mut entry : @manifest.AppEntry
  mut debug_level_value : Int
  mut title_overridden : Bool
  mut size_overridden : Bool
  mut titlebar_style_overridden : Bool
  mut entry_overridden : Bool
  mut debug_overridden : Bool
  mut bridge_startup_timeout_value_ms : Int
  mut menu : @native.MenuBar?
  extension_settings : Map[String, @manifest.ExtensionSetting]
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec]
  validation_errors : Array[AppConfigurationError]
}

///|
let default_bridge_startup_timeout_ms = 30000

///|
priv struct ResolvedAppConfig {
  manifest : @manifest.AppManifest
  base_dir : String?
}

///|
priv struct BridgeDispatchTask {
  request_id : Int64
  task : @async.Task[@native.BridgeResponse]
}

///|
priv struct CommandHostRuntime {
  host : @core.AppCommandHost
  destroy_hooks : Array[CommandExtensionDestroyHook]
  mut closed : Bool
}

///|
priv struct CommandExtensionDestroyHook {
  extension_id : String
  callback : () -> Unit raise
}

///|
priv struct BridgePagePolicy {
  dev_origin : String?
  request_timeout_ms : Int
}

///|
priv struct BridgeFrontendConfig {
  extensions : Array[@native.BridgeExtensionConfig]
  initialization_units : Array[@native.BridgeInitializationUnit]
}

///|
/// Failures while resolving and validating an application's configuration.
pub(all) suberror AppConfigurationError {
  InvalidSetting(name~ : String, message~ : String)
  Bootstrap(@bootstrap.BootstrapError)
  ExtensionDependencyCycle(extension_id~ : String)
  ExtensionUnavailable(
    extension_id~ : String,
    requested_by~ : String?,
    state~ : String
  )
  ExtensionAdaptationFailed(
    extension_id~ : String,
    error~ : @proton_extension.ExtensionAdapterError
  )
  InvalidJavaScriptNamespace(js_namespace~ : String)
  InvalidJavaScriptApi(js_namespace~ : String, api_name~ : String)
  InvalidDevelopmentUrl(url~ : String, reason~ : String)
} derive(Debug)

///|
/// Failures while loading the application's initial document.
pub(all) suberror AppEntryError {
  ReadFailed(path~ : String, detail~ : String)
  NativeLoad(action~ : String, error~ : @native.NativeError)
  ClosedDuringStartup
} derive(Debug)

///|
/// Failures in the MoonBit-side runtime wakeup source.
pub(all) suberror RuntimeWakeupError {
  UnsupportedFeature(feature~ : String)
  PipeCreateFailed(detail~ : String)
  SourceOpenFailed(source~ : String, detail~ : String)
  SourceClosed
  MissingNotification
} derive(Debug)

///|
/// Failures while starting or stopping command extensions.
pub(all) suberror CommandExtensionLifecycleError {
  RegistrationFailed(extension_id~ : String, detail~ : String)
  DestroyFailed(extension_id~ : String, detail~ : String)
} derive(Debug)

///|
/// Failures produced while configuring, starting, or running an application.
pub(all) suberror AppRunError {
  RunnerError(String)
  ConfigurationError(AppConfigurationError)
  NativeRuntimeError(action~ : String, error~ : @native.NativeError)
  RuntimeWakeupError(RuntimeWakeupError)
  CommandExtensionLifecycleError(CommandExtensionLifecycleError)
  EntryLoadError(AppEntryError)
  BridgeStartupError(@native.BridgeDiagnostic)
  BridgeRuntimeError(@native.BridgeDiagnostic)
  UnexpectedTaskFailure(detail~ : String)
} derive(Debug)
