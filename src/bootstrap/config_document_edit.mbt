///|
/// Converts one normalized extension setting back into its JSON representation.
fn extension_setting_to_json(setting : @manifest.ExtensionSetting) -> Json {
  match setting {
    Disabled => Json::boolean(false)
    Enabled(None) => Json::boolean(true)
    Enabled(Some(options)) => clone_json(options)
  }
}

///|
/// Converts one manifest window into its persisted JSON object form.
fn window_manifest_to_json(window : @manifest.WindowManifest) -> Json {
  let object : Map[String, Json] = {
    "title": Json::string(window.title),
    "width": ToJson::to_json(window.width),
    "height": ToJson::to_json(window.height),
  }
  match window.size_hint {
    @manifest.WindowSizeHint::None => ()
    @manifest.WindowSizeHint::Fixed =>
      object["size_hint"] = Json::string("fixed")
    @manifest.WindowSizeHint::Min => object["size_hint"] = Json::string("min")
    @manifest.WindowSizeHint::Max => object["size_hint"] = Json::string("max")
  }
  Json::object(object)
}

///|
/// Converts one manifest entry into its persisted JSON object form.
fn app_entry_to_json(entry : @manifest.AppEntry) -> Json {
  let object : Map[String, Json] = {}
  match entry {
    Html(value) => {
      object["kind"] = Json::string("html")
      object["value"] = Json::string(value)
    }
    Url(value) => {
      object["kind"] = Json::string("url")
      object["value"] = Json::string(value)
    }
    File(value) => {
      object["kind"] = Json::string("file")
      object["value"] = Json::string(value)
    }
    Asset(value) => {
      object["kind"] = Json::string("asset")
      object["value"] = Json::string(value)
    }
  }
  Json::object(object)
}

///|
/// Converts one secondary window manifest into its persisted JSON form.
fn app_window_manifest_to_json(window : @manifest.AppWindowManifest) -> Json {
  Json::object({
    "id": Json::string(window.id),
    "window": window_manifest_to_json(window.window),
    "entry": app_entry_to_json(window.entry),
  })
}

///|
/// Converts a typed runtime manifest into JSON.
///
/// User-facing app config files do not support `extensions`, but internal
/// framework process config still serializes code-declared extension settings.
pub fn app_manifest_to_json(manifest : @manifest.AppManifest) -> Json {
  let object : Map[String, Json] = {
    "window": window_manifest_to_json(manifest.window),
    "entry": app_entry_to_json(manifest.entry),
    "debug": ToJson::to_json(manifest.debug),
  }
  if manifest.windows.length() > 0 {
    object["windows"] = ToJson::to_json(
      manifest.windows.map(fn(window) { app_window_manifest_to_json(window) }),
    )
  }
  if manifest.extensions.length() > 0 {
    let extensions : Map[String, Json] = {}
    for name, setting in manifest.extensions {
      extensions[name] = extension_setting_to_json(setting)
    }
    object["extensions"] = Json::object(extensions)
  }
  Json::object(object)
}

///|
/// Returns the mutable `windows` array, creating it when necessary.
fn ensure_windows_json_array(object : Map[String, Json]) -> Array[Json] {
  match object.get("windows") {
    Some(Array(windows)) => windows
    _ => {
      let windows : Array[Json] = []
      object["windows"] = Json::array(windows)
      windows
    }
  }
}

///|
/// Extracts a secondary window id from raw JSON when present.
fn window_id_from_json(json : Json) -> String? {
  match json {
    Object(object) =>
      match object.get("id") {
        Some(String(id)) => Some(id)
        _ => None
      }
    _ => None
  }
}
