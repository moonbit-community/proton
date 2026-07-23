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
  mut entry_overridden : Bool
  mut debug_overridden : Bool
  mut bridge_startup_timeout_value_ms : Int
  mut menu : @native.MenuBar?
  extension_settings : Map[String, @manifest.ExtensionSetting]
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec]
  validation_errors : Array[String]
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
  destroy_hooks : Array[() -> Unit]
  mut closed : Bool
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
/// Failures produced while configuring, starting, or running an application.
pub(all) suberror AppRunError {
  RunnerError(String)
  ConfigurationError(String)
  NativeRuntimeError(@native.NativeError)
  EntryLoadError(String)
  BridgeStartupError(@native.BridgeDiagnostic)
  BridgeRuntimeError(@native.BridgeDiagnostic)
} derive(Debug)
