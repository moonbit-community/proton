///|
test "global hotkey metadata constants match generated app command extension" {
  assert_eq(extension().id(), "justjavac/proton-global-hotkey")
  assert_eq(extension().command_spec().unwrap().js_namespace(), "globalHotkey")
}
