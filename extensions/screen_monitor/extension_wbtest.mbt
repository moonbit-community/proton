///|
test "screen monitor extension identity matches the generated app command extension" {
  let capability = capability()
  assert_eq(capability.id(), "moonbit-community/proton-screen-monitor")
  let spec = capability.command_spec()
  assert_eq(spec.js_namespace(), "screen")
  assert_true(spec.op_names().contains("ext:screen/getDisplayMatching"))
  assert_false(spec.op_names().contains("ext:screen/drainEvents"))
  assert_eq(spec.scripts(), [])
  assert_true(capability.event_source() is Some(_))
}

///|
test "screen display matching request carries rectangle geometry" {
  let request = @screen_monitor_contract.MatchingRectRequest::{
    x: 10,
    y: 20,
    width: 300,
    height: 200,
  }
  assert_eq(request.width, 300)
  assert_eq(request.height, 200)
}
