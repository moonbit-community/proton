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
