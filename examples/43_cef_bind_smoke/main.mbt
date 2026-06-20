///|
let html =
  #| <html>
  #|   <body>
  #|     <script>
  #|       (function waitForBridge() {
  #|         if (typeof window.echo !== "function" || typeof window.done !== "function") {
  #|           setTimeout(waitForBridge, 20);
  #|           return;
  #|         }
  #|         window.echo("alpha", 42, { ok: true })
  #|           .then((reply) => {
  #|             if (!reply || reply.ok !== true || reply.args[0] !== "alpha" || reply.args[1] !== 42 || reply.args[2].ok !== true) {
  #|               return window.done("bad reply");
  #|             }
  #|             return window.done("ok");
  #|           })
  #|           .catch((error) => window.done(String(error)));
  #|       })();
  #|     </script>
  #|   </body>
  #| </html>

///|
async fn main {
  @async.sleep(0)
  let webview = @webview.Webview::new(debug=0)
  webview.set_title("CEF Bind Smoke")
  webview.set_size(320, 240, @webview.SizeHint::None)
  webview.bind("echo", fn(id, req) {
    let id = @ffi.from_cstr(id)
    let req = @ffi.from_cstr(req)
    webview.response(id, 0, "{\"ok\":true,\"args\":" + req + "}")
  })
  webview.bind("done", fn(id, req) {
    let id = @ffi.from_cstr(id)
    let req = @ffi.from_cstr(req)
    println(req)
    webview.response(id, 0, "null")
    webview.terminate()
  })
  webview.set_html(html)
  webview.run()
}
