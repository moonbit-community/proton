///|
test "app manifest stores windows" {
  let main_window = WindowManifest::new("Main", 960, 720)
  let settings_window = AppWindowManifest::new(
    "settings",
    WindowManifest::new("Settings", 420, 320, size_hint=Fixed),
    File("settings.html"),
  )
  let manifest = AppManifest::new(main_window, Html("<html></html>"), debug=2, windows=[
    settings_window,
  ])

  assert_eq(manifest.window.title, "Main")
  assert_eq(manifest.window.width, 960)
  assert_eq(manifest.window.height, 720)
  assert_eq(manifest.window.size_hint, None)
  assert_eq(manifest.debug, 2)
  @debug.assert_eq(manifest.windows, [settings_window])
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
  let manifest = AppManifest::new(
    WindowManifest::new("Main", 960, 720),
    Html("<html></html>"),
    windows~,
  )

  windows.push(
    AppWindowManifest::new(
      "later",
      WindowManifest::new("Later", 320, 240),
      File("later.html"),
    ),
  )
  assert_eq(manifest.windows.length(), 1)
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
