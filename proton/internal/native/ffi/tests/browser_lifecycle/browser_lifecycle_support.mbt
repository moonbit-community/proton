///|
extern "C" fn browser_accessibility_lifecycle_trace_ffi() -> Bytes = "proton_test_browser_accessibility_lifecycle_trace"

///|
pub fn browser_accessibility_lifecycle_trace() -> String {
  @ffi.link_runtime()
  @utf8.decode_lossy(browser_accessibility_lifecycle_trace_ffi())
}
