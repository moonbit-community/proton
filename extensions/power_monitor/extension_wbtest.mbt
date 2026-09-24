///|
test "power monitor extension identity matches the generated app command extension" {
  let capability = capability()
  assert_eq(capability.id(), "moonbit-community/proton-power-monitor")
  let spec = capability.command_spec()
  let host = @core.AppCommandHost()
  defer host.close()
  let spec = spec.register(host)
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

///|
test "watch failure is observable while the query monitor remains available" {
  defer cleanup_power_monitor()
  let monitor = ensure_monitor(watch=_ => {
    raise @sys_power_monitor.PowerMonitorError::BackendUnavailable(
      detail="watch fixture unavailable",
    )
  })
  assert_true(active_monitor.val is Some(_))
  assert_true(
    watch_status() is Unavailable(detail) &&
    detail.contains("watch fixture unavailable"),
  )
  // Reusing the monitor must not clear the watch failure or retry it.
  ignore(ensure_monitor())
  assert_true(watch_status() is Unavailable(_))
  ignore(monitor.power_source())
  assert_true(watch_status() is Unavailable(_))
}

///|
test "monitor creation failures retain their reason and cleanup clears status" {
  defer cleanup_power_monitor()
  try
    ignore(
      ensure_monitor(create=() => {
        raise @sys_power_monitor.PowerMonitorError::BackendUnavailable(
          detail="creation fixture unavailable",
        )
      }),
    )
  catch {
    BackendUnavailable(detail~) =>
      assert_true(detail.contains("creation fixture unavailable"))
    error => raise error
  } noraise {
    _ => fail("expected unavailable monitor")
  }
  assert_true(active_monitor.val is None)
  assert_true(
    watch_status() is Unavailable(detail) &&
    detail.contains("creation fixture unavailable"),
  )
  cleanup_power_monitor()
  assert_true(watch_status() is Stopped)
}
