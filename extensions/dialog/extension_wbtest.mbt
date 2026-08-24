///|
test "dialog metadata constants match generated app command extension" {
  assert_eq(extension().id(), "moonbit-community/proton-dialog")
  assert_eq(extension().command_spec().js_namespace(), "dialog")
}
