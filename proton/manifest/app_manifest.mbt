///|
/// Declarative application manifest consumed by the runtime.
pub struct AppManifest {
  window : WindowManifest
  entry : AppEntry
  windows : Array[AppWindowManifest]
  debug : Int
  extensions : Map[String, ExtensionSetting]
}

///|
/// Builds an app manifest.
/// The defaults match the minimal declarative shape accepted by bootstrap so
/// callers can opt into debug, extra windows, or extensions incrementally.
pub fn AppManifest::new(
  window : WindowManifest,
  entry : AppEntry,
  debug? : Int = 0,
  windows? : Array[AppWindowManifest] = [],
  extensions? : Map[String, ExtensionSetting] = Map([]),
) -> AppManifest {
  AppManifest::{
    window,
    entry,
    windows: windows.map(fn(window) { window }),
    debug,
    extensions: copy_extension_settings(extensions),
  }
}

///|
/// Returns one configured extension setting, if present in the manifest.
/// It returns `None` when the manifest does not mention the extension key at all.
pub fn AppManifest::extension_setting(
  self : AppManifest,
  name : String,
) -> ExtensionSetting? {
  self.extensions.get(name).map(copy_extension_setting)
}

///|
/// Returns the configured extension entries as name/setting pairs.
/// Each pair contains the manifest key together with its normalized declarative
/// enablement state and optional JSON options.
pub fn AppManifest::extension_settings(
  self : AppManifest,
) -> Array[(String, ExtensionSetting)] {
  let entries : Array[(String, ExtensionSetting)] = []
  for name, setting in self.extensions {
    entries.push((name, copy_extension_setting(setting)))
  }
  entries
}

///|
fn copy_extension_settings(
  settings : Map[String, ExtensionSetting],
) -> Map[String, ExtensionSetting] {
  let copied : Map[String, ExtensionSetting] = Map([])
  for name, setting in settings {
    copied[name] = copy_extension_setting(setting)
  }
  copied
}

///|
fn copy_extension_setting(setting : ExtensionSetting) -> ExtensionSetting {
  match setting {
    Disabled => Disabled
    Enabled(options) => Enabled(clone_json_option(options))
  }
}
