///|
test "app manifest constructor copies mutable inputs" {
  let windows = [
    @manifest.AppWindowManifest::AppWindowManifest(
      "settings",
      @manifest.WindowManifest::WindowManifest("Settings", 420, 320),
      File("settings.html"),
    ),
  ]
  let manifest = @manifest.AppManifest::AppManifest(
    @manifest.WindowManifest::WindowManifest("Main", 960, 720),
    Html("<html></html>"),
    windows~,
  )

  windows.push(
    @manifest.AppWindowManifest::AppWindowManifest(
      "later",
      @manifest.WindowManifest::WindowManifest("Later", 320, 240),
      File("later.html"),
    ),
  )
  assert_eq(manifest.windows.length(), 1)
}
