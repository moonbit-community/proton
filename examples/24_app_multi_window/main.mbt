///|
async fn main {
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("MoonBit Multi-Window", 980, 680),
    @manifest.AppEntry::File("24_app_multi_window/main_window.html"),
    debug=1,
    windows=[
      @manifest.AppWindowManifest::new(
        "docs",
        @manifest.WindowManifest::new("MoonBit Multi-Window Docs", 720, 560),
        @manifest.AppEntry::File("24_app_multi_window/docs_window.html"),
      ),
    ],
  )
  let app = match
    @proton.create_app(manifest, @proton.ExtensionRegistry::new()) {
    Ok(app) => app
    Err(error) => abort(error)
  }
  @async.sleep(0)
  app.run()
}
