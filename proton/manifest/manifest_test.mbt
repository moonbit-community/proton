///|
test "app manifest constructor copies mutable inputs" {
  let windows = [
    AppWindowManifest::AppWindowManifest(
      "settings",
      WindowManifest::WindowManifest("Settings", 420, 320),
      File("settings.html"),
    ),
  ]
  let manifest = AppManifest::AppManifest(
    WindowManifest::WindowManifest("Main", 960, 720),
    Html("<html></html>"),
    windows~,
  )

  windows.push(
    AppWindowManifest::AppWindowManifest(
      "later",
      WindowManifest::WindowManifest("Later", 320, 240),
      File("later.html"),
    ),
  )
  assert_eq(manifest.windows.length(), 1)
}
