///|
test "proton project dev_manifest keeps entry when dev_url is absent" {
  let loaded = LoadedAppManifest::new(
    @manifest.AppManifest::new(
      @manifest.WindowManifest::new("App", 800, 600),
      @manifest.AppEntry::Asset("frontend/dist/index.html"),
      debug=1,
    ),
    base_dir=Some("workspace/app"),
  )
  let project = ProtonProjectConfig::new(
    loaded,
    ProtonAppMetadata::new("App"),
    frontend=Some(ProtonFrontendConfig::new(dist=Some("frontend/dist"))),
  )

  let dev_loaded = project.dev_manifest()
  @debug.assert_eq(dev_loaded.base_dir(), Some("workspace/app"))
  match dev_loaded.manifest().entry {
    Asset(path) => assert_eq(path, "frontend/dist/index.html")
    _ => abort("expected original entry without frontend.dev_url")
  }
  assert_eq(dev_loaded.manifest().debug, 1)
}

///|
test "app_manifest_to_json roundtrips internal runtime manifest" {
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new(
      "Roundtrip",
      900,
      640,
      size_hint=@manifest.WindowSizeHint::Min,
      titlebar_style=@manifest.TitlebarStyle::Overlay,
    ),
    @manifest.AppEntry::Asset("frontend/index.html"),
    debug=1,
    windows=[
      @manifest.AppWindowManifest::new(
        "settings",
        @manifest.WindowManifest::new(
          "Settings",
          420,
          320,
          size_hint=@manifest.WindowSizeHint::Fixed,
        ),
        @manifest.AppEntry::Html("<html>Settings</html>"),
      ),
    ],
    extensions={
      "moonbit-community/proton-fs": @manifest.ExtensionSetting::enabled(),
      "moonbit-community/proton-tray": @manifest.ExtensionSetting::disabled(),
    },
    permissions=[
      @manifest.PermissionGrant::new(
        "main",
        @manifest.PermissionOrigin::App,
        "moonbit-community/proton-fs",
        scope=Json::object({ "read": Json::array([Json::string("./data")]) }),
      ),
    ],
  )
  let text = app_manifest_to_json(manifest).stringify(indent=2)
  let loaded = load_runtime_manifest_from_json(text)
  let roundtripped = loaded.manifest()
  assert_eq(roundtripped.window.title, "Roundtrip")
  assert_eq(roundtripped.window.size_hint, @manifest.WindowSizeHint::Min)
  assert_eq(
    roundtripped.window.titlebar_style,
    @manifest.TitlebarStyle::Overlay,
  )
  match roundtripped.entry {
    Asset(path) => assert_eq(path, "frontend/index.html")
    _ => abort("expected asset entry")
  }
  assert_eq(roundtripped.windows.length(), 1)
  assert_eq(
    roundtripped.windows[0].window.size_hint,
    @manifest.WindowSizeHint::Fixed,
  )
  @debug.assert_eq(
    roundtripped.extension_setting("moonbit-community/proton-fs"),
    Some(@manifest.ExtensionSetting::enabled()),
  )
  @debug.assert_eq(
    roundtripped.extension_setting("moonbit-community/proton-tray"),
    Some(@manifest.ExtensionSetting::disabled()),
  )
  let grants = roundtripped.permission_grants()
  assert_eq(grants.length(), 1)
  assert_eq(grants[0].window(), "main")
  assert_eq(grants[0].origin(), @manifest.PermissionOrigin::App)
  assert_eq(grants[0].extension(), "moonbit-community/proton-fs")
}
