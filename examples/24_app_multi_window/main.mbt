///|
async fn main {
  let app = @app.file(
    "MoonBit Multi-Window",
    980,
    680,
    "24_app_multi_window/main_window.html",
    debug=1,
  ).window_file(
    "docs", "MoonBit Multi-Window Docs", 720, 560, "24_app_multi_window/docs_window.html",
  )
  app.run_or_abort()
}
