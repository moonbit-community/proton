///|
extern "C" fn cef_execute_process_ffi() -> Int = "lepus_cef_execute_process"

///|
fn main {
  ignore(@webview.backend_id())
  let code = cef_execute_process_ffi()
  @sys.exit(if code >= 0 { code } else { 0 })
}
