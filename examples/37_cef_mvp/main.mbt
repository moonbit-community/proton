///|
fn page_html(backend : String, detail : String) -> String {
  (
    $|<!doctype html>
    $|<html>
    $|  <head>
    $|    <meta charset="utf-8" />
    $|    <title>Moonbit Backend MVP</title>
    $|  </head>
    $|  <body style="background: white;">
    $|    <h1>Moonbit Backend MVP</h1>
    $|    <p>Active backend: <code>\{backend}</code></p>
    $|    <p>Status: \{detail}</p>
    $|  </body>
    $|</html>
  )
}

///|
async fn main {
  @async.sleep(0)
  let backend = @webview.backend_id()
  let available = @webview.backend_available()
  if !available {
    println(
      "CEF backend is not linked. Set LEPUS_CEF_ROOT before building this example.",
    )
    return
  }
  let webview = @webview.Webview::new(debug=1)
  println("Lepus browser backend: " + backend)
  println("Backend available: true")
  webview
  ..set_title("Lepus Browser Backend MVP")
  ..set_size(820, 560, @webview.SizeHint::None)
  ..set_html(page_html(backend, "CEF backend is active."))
  .run()
}
