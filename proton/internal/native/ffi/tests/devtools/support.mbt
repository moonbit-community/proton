///|
extern "C" fn check_lifetime_ffi() -> Int = "moonbit_proton_devtools_test_lifetime"

///|
pub fn check_lifetime() -> Int {
  @ffi.ensure_cef_loader_linked()
  check_lifetime_ffi()
}
