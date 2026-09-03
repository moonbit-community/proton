///|
extern "C" fn browser_accessibility_lifecycle_trace_ffi() -> Bytes = "proton_test_browser_accessibility_lifecycle_trace"

///|
pub fn browser_accessibility_lifecycle_trace() -> String {
  let _ = @ffi.proton_abi_version_ffi()
  @utf8.decode_lossy(browser_accessibility_lifecycle_trace_ffi())
}
