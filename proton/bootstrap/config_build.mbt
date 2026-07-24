///|
/// Converts the root JSON object into a typed loaded manifest.
fn build_loaded_manifest_from_json(
  json : Json,
  base_dir : String?,
  allow_extensions? : Bool = false,
) -> LoadedAppManifest raise BootstrapError {
  let object = expect_object(json, "app manifest")
  reject_unsupported_permissions_field(object)
  LoadedAppManifest::new(
    build_app_manifest_from_object(object, base_dir, allow_extensions~),
    base_dir~,
  )
}

///|
/// Builds a manifest window config from a JSON object.
fn build_window_manifest_from_json(
  json : Json,
) -> @manifest.WindowManifest raise BootstrapError {
  build_window_manifest_from_object(expect_object(json, "window manifest"))
}

///|
/// Builds a typed manifest from the root manifest object fields.
fn build_app_manifest_from_object(
  object : Map[String, Json],
  base_dir : String?,
  allow_extensions? : Bool = false,
) -> @manifest.AppManifest raise BootstrapError {
  let window = build_required_window_from_object(object)
  let entry = build_required_entry_from_object(object, base_dir)
  let windows = build_optional_windows_from_object(object, base_dir)
  let extensions = build_declared_extension_settings_from_object(
    object,
    allow_extensions~,
  )
  let debug = build_debug_value_from_object(object)
  @manifest.AppManifest::new(
    window,
    entry,
    debug=int_or_default(debug, 0),
    windows~,
    extensions~,
  )
}

///|
/// Builds the required primary window field from the root manifest object.
fn build_required_window_from_object(
  object : Map[String, Json],
) -> @manifest.WindowManifest raise BootstrapError {
  required_built_field(
    object, "window", "app manifest.window", build_window_manifest_from_json,
  )
}

///|
/// Builds the required primary entry field from the root manifest object.
fn build_required_entry_from_object(
  object : Map[String, Json],
  base_dir : String?,
) -> @manifest.AppEntry raise BootstrapError {
  required_built_field(object, "entry", "app manifest.entry", entry_json => {
    build_app_entry_from_json(entry_json, base_dir)
  })
}

///|
/// Builds the optional secondary windows field from the root manifest object.
fn build_optional_windows_from_object(
  object : Map[String, Json],
  base_dir : String?,
) -> Array[@manifest.AppWindowManifest] raise BootstrapError {
  build_app_windows_from_json(optional_field(object, "windows"), base_dir)
}

///|
/// Builds extension settings for internal runtime manifests.
fn build_declared_extension_settings_from_object(
  object : Map[String, Json],
  allow_extensions? : Bool = false,
) -> Map[String, @manifest.ExtensionSetting] raise BootstrapError {
  if !allow_extensions && object.get("extensions") is Some(_) {
    raise UnsupportedField(
      path="app manifest.extensions",
      reason="declare extensions in MoonBit code with .extension(...)",
    )
  }
  build_extension_settings(optional_field(object, "extensions"))
}

///|
/// Builds the optional debug field from the root manifest object.
fn build_debug_value_from_object(
  object : Map[String, Json],
) -> Int? raise BootstrapError {
  decode_optional_int(optional_field(object, "debug"), "app manifest.debug")
}

///|
/// Rejects unsupported permissions fields on the root manifest object.
fn reject_unsupported_permissions_field(
  object : Map[String, Json],
) -> Unit raise BootstrapError {
  reject_unsupported_permissions(optional_field(object, "permissions"))
}

///|
/// Builds a manifest window config from an already validated object.
fn build_window_manifest_from_object(
  object : Map[String, Json],
) -> @manifest.WindowManifest raise BootstrapError {
  let title = required_string_field(object, "title", "window.title")
  let width = required_int_field(object, "width", "window.width")
  let height = required_int_field(object, "height", "window.height")
  let size_hint = parse_size_hint(
    decode_optional_string(
      optional_field(object, "size_hint"),
      "window.size_hint",
    ),
  )
  let titlebar_style = parse_titlebar_style(
    decode_optional_string(
      optional_field(object, "titlebar_style"),
      "window.titlebar_style",
    ),
  )
  @manifest.WindowManifest::new(
    title,
    width,
    height,
    size_hint~,
    titlebar_style~,
  )
}

///|
/// Builds an app entry value and rebases relative file-backed entries against the config directory.
fn build_app_entry_from_json(
  json : Json,
  base_dir : String?,
) -> @manifest.AppEntry raise BootstrapError {
  let object = expect_object(json, "app entry")
  build_app_entry_from_parts(
    required_string_field(object, "kind", "entry.kind"),
    required_string_field(object, "value", "entry.value"),
    base_dir,
  )
}

///|
/// Builds an app entry from decoded `kind` and `value` fields.
fn build_app_entry_from_parts(
  kind : String,
  value : String,
  base_dir : String?,
) -> @manifest.AppEntry raise BootstrapError {
  let normalized_kind = normalize_keyword(kind)
  let rebased_value = match normalized_kind {
    "file" => rebase_relative_path(value, base_dir)
    "asset" => rebase_relative_path(value, base_dir)
    _ => value
  }
  match normalized_kind {
    "html" => @manifest.AppEntry::Html(rebased_value)
    "url" => @manifest.AppEntry::Url(rebased_value)
    "file" => @manifest.AppEntry::File(rebased_value)
    "asset" => @manifest.AppEntry::Asset(rebased_value)
    _ => raise UnsupportedValue(path="app entry kind", value=kind)
  }
}

///|
/// Builds the optional secondary window list from JSON.
fn build_app_windows_from_json(
  json : Json?,
  base_dir : String?,
) -> Array[@manifest.AppWindowManifest] raise BootstrapError {
  match json {
    None => []
    Some(Array(items)) => build_app_windows_from_array(items, base_dir)
    Some(_) =>
      raise InvalidField(
        path="app manifest.windows",
        expectation="must be an array",
      )
  }
}

///|
/// Builds every secondary window from the decoded `windows` array.
fn build_app_windows_from_array(
  items : Array[Json],
  base_dir : String?,
) -> Array[@manifest.AppWindowManifest] raise BootstrapError {
  let windows : Array[@manifest.AppWindowManifest] = []
  for index, item in items {
    windows.push(build_app_window_from_json(item, base_dir, index))
  }
  windows
}

///|
/// Builds one secondary window config entry from the `windows` array.
fn build_app_window_from_json(
  json : Json,
  base_dir : String?,
  index : Int,
) -> @manifest.AppWindowManifest raise BootstrapError {
  let label = "windows[" + index.to_string() + "]"
  build_app_window_from_object(expect_object(json, label), base_dir, label)
}

///|
/// Builds one secondary window config entry from an already validated object.
fn build_app_window_from_object(
  object : Map[String, Json],
  base_dir : String?,
  label : String,
) -> @manifest.AppWindowManifest raise BootstrapError {
  let id = required_string_field(object, "id", label + ".id")
  let window = required_built_field(
    object,
    "window",
    label + ".window",
    build_window_manifest_from_json,
  )
  let entry = required_built_field(object, "entry", label + ".entry", entry_json => {
    build_app_entry_from_json(entry_json, base_dir)
  })
  @manifest.AppWindowManifest::new(id, window, entry)
}

///|
/// Builds the normalized extension settings map from the `extensions` object.
fn build_extension_settings(
  json : Json?,
) -> Map[String, @manifest.ExtensionSetting] raise BootstrapError {
  match json {
    None => Map([])
    Some(Object(object)) => build_extension_settings_from_object(object)
    Some(_) =>
      raise InvalidField(
        path="app manifest.extensions",
        expectation="must be an object",
      )
  }
}

///|
/// Builds the normalized extension settings map from an already validated object.
fn build_extension_settings_from_object(
  object : Map[String, Json],
) -> Map[String, @manifest.ExtensionSetting] raise BootstrapError {
  let settings : Map[String, @manifest.ExtensionSetting] = Map([])
  for name, value in object {
    guard normalize_keyword(name) != "" else {
      raise InvalidField(
        path="app manifest.extensions",
        expectation="must not contain an empty key",
      )
    }
    settings.set(name, build_extension_setting_from_json(name, value))
  }
  settings
}

///|
/// Builds one normalized extension setting from the raw JSON value.
fn build_extension_setting_from_json(
  name : String,
  value : Json,
) -> @manifest.ExtensionSetting raise BootstrapError {
  match value {
    True => @manifest.ExtensionSetting::enabled()
    False => @manifest.ExtensionSetting::disabled()
    Object(options) =>
      @manifest.ExtensionSetting::enabled(
        options=Some(Json::object(clone_json_object(options))),
      )
    _ =>
      raise InvalidField(
        path="app manifest.extensions." + name,
        expectation="must be a boolean or object",
      )
  }
}

///|
/// Rejects unsupported `permissions` config.
fn reject_unsupported_permissions(json : Json?) -> Unit raise BootstrapError {
  match json {
    None => ()
    Some(_) =>
      raise UnsupportedField(
        path="app manifest.permissions",
        reason="permissions are not implemented",
      )
  }
}
