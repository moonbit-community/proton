///|
/// MoonBit bridge example modeled after Tauri Hellworld but in MoonBit style.
/// It exposes a host function `greet` to the frontend and renders a minimal UI.
fn main {
  let webview = @webview.Webview::new(debug=1)
  webview.set_title("MoonBit Tauri-like Hello World")
  webview.set_size(800, 600, @webview.SizeHint::None)
  webview.bind("greet", fn(id, req) {
    let id = @ffi.from_cstr(id)
    let raw_req = @ffi.from_cstr(req)
    let name = try {
      let request_json : Json = @json.parse(raw_req)
      let args : Array[String] = @json.from_json(request_json)
      if args.length() > 0 {
        args[0]
      } else {
        "world"
      }
    } catch {
      _ => "world"
    }
    let result = "{\"message\":\"Hello \{name}, You have been greeted from Moonbit!\", \"req\":" +
      raw_req +
      "}"
    println(id)
    println(raw_req)
    println(result)
    webview.response(id, 0, result)
  })
  // Load embedded HTML resource produced from index.html via pre-build
  webview.set_html(resource)
  webview.run()
}
