///|
test "extension setting helpers preserve enabled state and options" {
  let options = Json::object({ "scope": Json::string("read") })
  let enabled = ExtensionSetting::enabled(options=Some(options))
  assert_true(enabled.is_enabled())
  @debug.assert_eq(enabled.options(), Some(options))

  let disabled = ExtensionSetting::disabled()
  assert_false(disabled.is_enabled())
  @debug.assert_eq(disabled.options(), None)
}

///|
test "extension setting options are deep snapshots" {
  let options = Json::object({ "nested": Json::empty_object() })
  let enabled = ExtensionSetting::enabled(options=Some(options))
  match options {
    Object(object) => object["late"] = Json::boolean(true)
    _ => abort("expected object options")
  }
  match enabled.options() {
    Some(Object(object)) => {
      @debug.assert_eq(object.get("late"), None)
      object["exposed"] = Json::boolean(true)
    }
    _ => abort("expected enabled object options")
  }
  match enabled.options() {
    Some(Object(object)) => @debug.assert_eq(object.get("exposed"), None)
    _ => abort("expected fresh enabled object options")
  }
}

///|
test "app manifest stores windows and extension settings" {
  let main_window = WindowManifest::new("Main", 960, 720)
  let settings_window = AppWindowManifest::new(
    "settings",
    WindowManifest::new("Settings", 420, 320, size_hint=Fixed),
    File("settings.html"),
  )
  let manifest = AppManifest::new(
    main_window,
    Html("<html></html>"),
    debug=2,
    windows=[settings_window],
    extensions={
      "justjavac/proton-fs": ExtensionSetting::enabled(
        options=Some(Json::object({ "scope": Json::string("read") })),
      ),
      "justjavac/proton-dialog": ExtensionSetting::disabled(),
    },
  )

  assert_eq(manifest.window.title, "Main")
  assert_eq(manifest.window.width, 960)
  assert_eq(manifest.window.height, 720)
  assert_eq(manifest.window.size_hint, None)
  assert_eq(manifest.debug, 2)
  @debug.assert_eq(manifest.windows, [settings_window])
  @debug.assert_eq(
    manifest.extension_setting("justjavac/proton-fs"),
    Some(
      ExtensionSetting::enabled(
        options=Some(Json::object({ "scope": Json::string("read") })),
      ),
    ),
  )
  @debug.assert_eq(
    manifest.extension_setting("justjavac/proton-dialog"),
    Some(ExtensionSetting::disabled()),
  )
  @debug.assert_eq(manifest.extension_setting("justjavac/proton-path"), None)
  assert_eq(manifest.extension_settings().length(), 2)
}

///|
test "app manifest constructor copies mutable inputs" {
  let windows = [
    AppWindowManifest::new(
      "settings",
      WindowManifest::new("Settings", 420, 320),
      File("settings.html"),
    ),
  ]
  let extensions = { "justjavac/proton-fs": ExtensionSetting::enabled() }
  let manifest = AppManifest::new(
    WindowManifest::new("Main", 960, 720),
    Html("<html></html>"),
    windows~,
    extensions~,
  )

  windows.push(
    AppWindowManifest::new(
      "later",
      WindowManifest::new("Later", 320, 240),
      File("later.html"),
    ),
  )
  extensions["justjavac/proton-dialog"] = ExtensionSetting::enabled()

  assert_eq(manifest.windows.length(), 1)
  @debug.assert_eq(manifest.extension_setting("justjavac/proton-dialog"), None)
}

///|
test "app manifest extension settings expose option snapshots" {
  let options = Json::object({ "scope": Json::string("read") })
  let extensions = {
    "justjavac/proton-fs": ExtensionSetting::enabled(options=Some(options)),
  }
  let manifest = AppManifest::new(
    WindowManifest::new("Main", 960, 720),
    Html("<html></html>"),
    extensions~,
  )
  match options {
    Object(object) => object["late"] = Json::boolean(true)
    _ => abort("expected object options")
  }
  match manifest.extension_setting("justjavac/proton-fs") {
    Some(ExtensionSetting::Enabled(Some(Object(object)))) => {
      @debug.assert_eq(object.get("late"), None)
      object["exposed"] = Json::boolean(true)
    }
    _ => abort("expected fs extension options")
  }
  match manifest.extension_setting("justjavac/proton-fs") {
    Some(ExtensionSetting::Enabled(Some(Object(object)))) =>
      @debug.assert_eq(object.get("exposed"), None)
    _ => abort("expected fresh fs extension options")
  }
  let entries = manifest.extension_settings()
  match entries[0] {
    (_, ExtensionSetting::Enabled(Some(Object(object)))) =>
      object["entry"] = Json::boolean(true)
    _ => abort("expected extension settings entry")
  }
  match manifest.extension_setting("justjavac/proton-fs") {
    Some(ExtensionSetting::Enabled(Some(Object(object)))) =>
      @debug.assert_eq(object.get("entry"), None)
    _ => abort("expected fresh fs extension options after entries")
  }
}

///|
test "app manifest supports asset-backed entries" {
  let manifest = AppManifest::new(
    WindowManifest::new("Assets", 960, 720),
    Asset("frontend/index.html"),
  )

  match manifest.entry {
    Asset(path) => assert_eq(path, "frontend/index.html")
    _ => abort("expected asset entry")
  }
}
