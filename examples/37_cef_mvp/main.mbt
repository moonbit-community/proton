///|
let cef_unavailable_message = "CEF backend is optional and is not linked in this binary."

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
fn run_system_webview(detail : String) -> Unit {
  @webview.Webview::new(debug=1)
  ..set_title("Lepus Browser Backend MVP")
  ..set_size(820, 560, @webview.SizeHint::None)
  ..set_html(page_html("system-webview", detail))
  .run()
}

///|
fn run_cef_if_available() -> Bool {
  if !@cef.is_available() {
    return false
  }
  match
    @cef.CefRuntime::initialize(
      settings=@cef.CefSettings::new(
        debug=true,
        remote_debugging_port=Some(9222),
      ),
    ) {
    Ok(runtime) =>
      match
        runtime.create_view(
          options=@cef.CefWindowOptions::new(
            title="Lepus Browser Backend MVP",
            width=820,
            height=560,
          ),
        ) {
        Ok(view) => {
          ignore(view.set_html(page_html("cef", "CEF backend is active.")))
          ignore(runtime.run())
          ignore(view.destroy())
          ignore(runtime.destroy())
          true
        }
        Err(error) => {
          ignore(runtime.destroy())
          run_system_webview(
            "CEF was linked but failed to create a view: " + error,
          )
          true
        }
      }
    Err(error) => {
      run_system_webview("CEF was selected but failed to initialize: " + error)
      true
    }
  }
}

///|
fn main {
  println("Lepus browser backend: " + @cef.backend_id())
  println("CEF linked: \{@cef.is_available()}")
  if !run_cef_if_available() {
    println(cef_unavailable_message)
    run_system_webview(cef_unavailable_message)
  }
}
