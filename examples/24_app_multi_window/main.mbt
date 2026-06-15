///|
fn main {
  let app : @wvrt.App = match
    @app.AppBuilder::file(
      "MoonBit Multi-Window",
      980,
      680,
      "24_app_multi_window/main_window.html",
      debug=1,
    )
    .window_file(
      "docs", "MoonBit Multi-Window Docs", 720, 560, "24_app_multi_window/docs_window.html",
    )
    .build() {
    Ok(app) => app
    Err(error) => abort(error)
  }
  app.run()
}
