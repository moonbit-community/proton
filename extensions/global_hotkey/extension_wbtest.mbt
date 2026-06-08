///|
test "global hotkey metadata constants match generated app command extension" {
  assert_eq(
    generated_app_command_extension().id(),
    "justjavac/lepus-global-hotkey",
  )
  assert_eq(generated_app_command_extension().js_namespace(), "globalHotkey")
}
