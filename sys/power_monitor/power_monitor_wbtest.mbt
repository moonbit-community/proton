///|
test "decode_native_detail falls back when ffi output is empty" {
  assert_eq(decode_native_detail(@utf8.encode("")), "")
  assert_eq(
    decode_native_detail(@utf8.encode("native failure")),
    "native failure",
  )
}

///|
test "power_source_from_native_code maps native codes" {
  assert_true(power_source_from_native_code(0) == Unknown)
  assert_true(power_source_from_native_code(1) == AC)
  assert_true(power_source_from_native_code(2) == Battery)
  assert_true(power_source_from_native_code(99) == Unknown)
}

///|
test "power_monitor_event_from_native_code maps native codes" {
  assert_true(power_monitor_event_from_native_code(0) == Suspend)
  assert_true(power_monitor_event_from_native_code(1) == Resume)
  assert_true(power_monitor_event_from_native_code(2) == OnAC)
  assert_true(power_monitor_event_from_native_code(3) == OnBattery)
  assert_true(power_monitor_event_from_native_code(4) == LockScreen)
  assert_true(power_monitor_event_from_native_code(5) == UnlockScreen)
  assert_true(power_monitor_event_from_native_code(99) == Suspend)
}

///|
test "destroyed power monitor cannot restart watching or take events" {
  // Exercise lifecycle validation even when the power backend is unavailable.
  let monitor = PowerMonitor::{ handle: native_create(), }
  monitor.destroy()
  try monitor.start_watching() catch {
    OperationFailed(operation~, detail~) => {
      assert_eq(operation, "start_watching")
      assert_eq(detail, "power monitor has been destroyed")
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("destroyed monitor restarted watching")
  }
  assert_eq(
    native_take_event(monitor.handle, Ref(0)),
    native_status_operation_failed,
  )
  assert_true(monitor.drain_events().is_empty())
  monitor.destroy()
}
