///|
test "global hotkey metadata constants match generated app command extension" {
  assert_eq(extension_definition.id(), "moonbit-community/proton-global-hotkey")
  let capability = capability()
  let spec = capability.command_spec()
  assert_eq(spec.js_namespace(), "globalHotkey")
  assert_false(spec.op_names().contains("ext:globalHotkey/drainTriggered"))
  assert_eq(spec.scripts(), [])
  assert_true(capability.event_source() is Some(_))
}
