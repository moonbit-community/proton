///|
test "dialog level maps to native code" {
  @debug.assert_eq(level_to_native(None), @native.DialogLevel::Info)
  @debug.assert_eq(
    level_to_native(Some("warning")),
    @native.DialogLevel::Warning,
  )
  @debug.assert_eq(level_to_native(Some("error")), @native.DialogLevel::Error)
}

///|
test "dialog metadata constants match generated app command extension" {
  assert_eq(extension().id(), "justjavac/proton-dialog")
  assert_eq(extension().command_spec().unwrap().js_namespace(), "dialog")
}
