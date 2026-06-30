///|
/// High-level application facade for ordinary Proton apps.
struct App {
  file_path : String?
  mut asset_dir : String?
  mut window : @manifest.WindowManifest
  mut entry : @manifest.AppEntry
  mut debug_level_value : Int
  mut title_overridden : Bool
  mut size_overridden : Bool
  mut entry_overridden : Bool
  mut debug_overridden : Bool
  extension_settings : Map[String, @manifest.ExtensionSetting]
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec]
  validation_errors : Array[String]
}

///|
priv struct BridgeDispatchTask {
  request_id : Int64
  task : @async.Task[@native.BridgeResponse]
}
