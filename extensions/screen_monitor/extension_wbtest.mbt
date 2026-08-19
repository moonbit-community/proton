///|
test "screen monitor extension identity matches the generated app command extension" {
  assert_eq(extension().id(), "moonbit-community/proton-screen-monitor")
  assert_eq(extension().command_spec().js_namespace(), "screen")
}
