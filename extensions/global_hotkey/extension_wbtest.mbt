///|
test "global hotkey metadata constants match generated app command extension" {
  assert_eq(extension().id(), "moonbit-community/proton-global-hotkey")
  assert_eq(extension().command_spec().js_namespace(), "globalHotkey")
}
