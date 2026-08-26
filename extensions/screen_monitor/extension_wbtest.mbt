///|
test "screen monitor extension identity matches the generated app command extension" {
  let capability = capability()
  assert_eq(capability.id(), "moonbit-community/proton-screen-monitor")
  let spec = capability.command_spec()
  assert_eq(spec.js_namespace(), "screen")
  assert_false(spec.op_names().contains("ext:screen/drainEvents"))
  assert_eq(spec.scripts(), [])
  assert_true(capability.event_source() is Some(_))
}
