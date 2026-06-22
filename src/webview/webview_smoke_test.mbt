///|
fn cef_unit_tests_enabled() -> Bool {
  match @sys.get_env_var("PROTON_RUN_CEF_UNIT_TESTS") {
    Some("1") => backend_available()
    _ => false
  }
}

///|
test "CEF webview lifecycle and binding smoke" {
  guard cef_unit_tests_enabled() else { return }
  let mut called = false
  let mut callback_id = ""
  let mut callback_req = ""
  let webview = Webview::new()
  webview.set_title("Test")
  webview.set_size(480, 320, SizeHint::None)
  webview.bind("press", fn(id, req) {
    callback_id = @ffi.from_cstr(id)
    callback_req = @ffi.from_cstr(req)
    called = true
    webview.response(callback_id, 0, "{\"ok\":true}")
    webview.terminate()
  })
  webview.set_html(
    (
      #| <html>
      #|   <body>
      #|     <script>
      #|       window.addEventListener("load", () => {
      #|         window.setTimeout(() => {
      #|           window.press("hello", 123).catch((error) => {
      #|             document.body.textContent = String(error);
      #|           });
      #|         }, 0);
      #|       });
      #|     </script>
      #|   </body>
      #| </html>,
    ),
  )
  webview.run()
  webview.destroy()
  webview.destroy()
  assert_true(called)
  assert_true(!callback_id.is_empty())
  assert_eq(callback_req, "[\"hello\",123]")
}
