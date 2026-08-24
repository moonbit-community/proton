///|
test "screen monitor extension identity matches the generated app command extension" {
  assert_eq(capability().id(), "moonbit-community/proton-screen-monitor")
  assert_eq(capability().command_spec().js_namespace(), "screen")
}
