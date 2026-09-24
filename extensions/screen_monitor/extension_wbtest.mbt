///|
test "screen monitor extension identity matches the generated app command extension" {
  let capability = capability()
  assert_eq(capability.id(), "moonbit-community/proton-screen-monitor")
  let spec = capability.command_spec()
  let host = @core.AppCommandHost()
  defer host.close()
  let spec = spec.register(host)
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

///|
test "watch failure is observable while the query monitor remains available" {
  defer cleanup_screen_monitor()
  let monitor = ensure_monitor(watch=_ => {
    raise @sys_screen_monitor.ScreenMonitorError::BackendUnavailable(
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
  ignore(monitor.displays())
  assert_true(watch_status() is Unavailable(_))
}

///|
test "monitor creation failures retain their reason and cleanup clears status" {
  defer cleanup_screen_monitor()
  try
    ignore(
      ensure_monitor(create=() => {
        raise @sys_screen_monitor.ScreenMonitorError::BackendUnavailable(
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
  cleanup_screen_monitor()
  assert_true(watch_status() is Stopped)
}
