///|
extern "C" fn runtime_alert_test() -> Int32 = "proton_test_runtime_alert"

///|
test "runtime alerts lay out diagnostics and complete without showing windows" {
  @ffi.link_runtime()
  let result = runtime_alert_test()
  guard result != -1 else { return }
  assert_eq(result, 0)
}
