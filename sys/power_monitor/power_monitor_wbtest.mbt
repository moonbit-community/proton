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
async test "destroyed power monitor cannot restart watching or take events" {
  // Exercise lifecycle validation even when the power backend is unavailable.
  let monitor = PowerMonitor::{ handle: native_create(), watching: false, }
  monitor.destroy()
  try
    monitor.with_watching(() => {
      fail("destroyed monitor started")
      ()
    })
  catch {
    PowerMonitorError::OperationFailed(operation~, detail~) => {
      assert_eq(operation, "with_watching")
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

///|
#cfg(not(platform="windows"))
async test "completion pipe read end reaches EOF through a raw-fd stream" {
  let monitor = PowerMonitor::{ handle: native_create(), watching: false, }
  let write_fd = Ref(-1)
  let read_fd = native_open_completion_pipe(monitor.handle, write_fd)
  assert_true(read_fd >= 0 && write_fd.val >= 0)
  let reader = @raw_fd.RawFdStream(native_completion_fd(read_fd))
  defer reader.close()
  // Closing the only write end is how the native watcher reports teardown.
  native_close_fd(write_fd.val)
  assert_eq(reader.read_all(), b"")
  monitor.destroy()
}
