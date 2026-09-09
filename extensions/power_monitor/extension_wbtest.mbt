///|
test "power monitor extension identity matches the generated app command extension" {
  let capability = capability()
  assert_eq(capability.id(), "moonbit-community/proton-power-monitor")
  let spec = capability.command_spec()
  assert_eq(spec.js_namespace(), "powerMonitor")
  assert_true(spec.op_names().contains("ext:powerMonitor/getSystemIdleState"))
  assert_false(spec.op_names().contains("ext:powerMonitor/drainEvents"))
  assert_eq(spec.scripts(), [])
  assert_true(capability.event_source() is Some(_))
}

///|
test "power monitor idle state request preserves threshold" {
  let request = @power_monitor_contract.IdleStateRequest::{
    idle_threshold: 30,
  }
  assert_eq(request.idle_threshold, 30)
  let reply = @power_monitor_contract.IdleStateReply::{ state: "active", }
  assert_eq(reply.state, "active")
}
