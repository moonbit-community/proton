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
    Disabled => false
    Enabled => true
  }
}

///|
/// Converts one manifest window into its internal runtime JSON object form.
fn window_manifest_to_json(window : @manifest.WindowManifest) -> Json {
  let object : Map[String, Json] = {
    "title": window.title,
    "width": window.width,
    "height": window.height,
  }
  match window.size_hint {
    @manifest.WindowSizeHint::None => ()
    @manifest.WindowSizeHint::Fixed => object["size_hint"] = Json("fixed")
    @manifest.WindowSizeHint::Min => object["size_hint"] = Json("min")
    @manifest.WindowSizeHint::Max => object["size_hint"] = Json("max")
  }
  match window.titlebar_style {
    @manifest.TitlebarStyle::Default => ()
    @manifest.TitlebarStyle::Overlay =>
      object["titlebar_style"] = Json("overlay")
  }
  Json::object(object)
}

///|
/// Converts one manifest entry into its internal runtime JSON object form.
fn app_entry_to_json(entry : @manifest.AppEntry) -> Json {
  match entry {
    Html(value) => { "kind": "html", "value": value }
    Url(value) => { "kind": "url", "value": value }
    File(value) => { "kind": "file", "value": value }
    Asset(value) => { "kind": "asset", "value": value }
  }
}

///|
/// Converts one secondary window manifest into internal runtime JSON.
fn app_window_manifest_to_json(window : @manifest.AppWindowManifest) -> Json {
  {
    "id": window.id,
    "window": window_manifest_to_json(window.window),
    "entry": app_entry_to_json(window.entry),
    "open_on_start": window.open_on_start,
  }
}

///|
fn permission_grant_to_json(grant : @manifest.PermissionGrant) -> Json {
  {
    "window": grant.window(),
    "origin": match grant.origin() {
      App => "app"
      Entry => "entry"
    },
    "extension": grant.extension(),
    "scope": grant.scope(),
  }
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
  if manifest.permissions.length() > 0 {
    object["permissions"] = Json::array(
      manifest.permissions.map(permission_grant_to_json),
    )
  }
  Json::object(object)
}
