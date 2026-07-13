///|
/// Deep-clones a JSON value so extension options do not alias the source tree.
fn clone_json(json : Json) -> Json {
  match json {
    Array(items) => Json::array(items.map(item => clone_json(item)))
    Object(object) => Json::object(clone_json_object(object))
    _ => json
  }
}

///|
/// Deep-clones a JSON object map entry by entry.
fn clone_json_object(object : Map[String, Json]) -> Map[String, Json] {
  let cloned : Map[String, Json] = Map([])
  for key, value in object {
    cloned.set(key, clone_json(value))
  }
  cloned
}

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
/// Converts one manifest window into its internal runtime JSON object form.
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
/// Converts one manifest entry into its internal runtime JSON object form.
fn app_entry_to_json(entry : @manifest.AppEntry) -> Json {
  let object : Map[String, Json] = Map([])
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
/// Converts one secondary window manifest into internal runtime JSON.
fn app_window_manifest_to_json(window : @manifest.AppWindowManifest) -> Json {
  Json::object({
    "id": Json::string(window.id),
    "window": window_manifest_to_json(window.window),
    "entry": app_entry_to_json(window.entry),
  })
}

///|
/// Converts a typed runtime manifest into JSON for native runtime handoff.
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
    let extensions : Map[String, Json] = Map([])
    for name, setting in manifest.extensions {
      extensions[name] = extension_setting_to_json(setting)
    }
    object["extensions"] = Json::object(extensions)
  }
  Json::object(object)
}
