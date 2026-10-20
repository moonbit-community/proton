///|
extern "C" fn test_screen_event_snapshots() -> Int32 = "proton_test_screen_event_snapshots"

///|
test "native screen queue retains removed and changed display snapshots" {
  // A value-level FFI call pulls native_common.o from the production archive
  // before the test archive is scanned by one-pass linkers.
  let monitor = @proton_screen_monitor.ScreenMonitor()
  defer monitor.destroy()
  assert_eq(test_screen_event_snapshots(), 1)
}

///|
#cfg(platform="linux")
extern "C" fn test_screen_watch_startup() -> Int32 = "proton_test_screen_watch_startup"

///|
#cfg(platform="linux")
test "Linux screen watch publishes its startup result before notifying and can restart" {
  let monitor = @proton_screen_monitor.ScreenMonitor()
  defer monitor.destroy()
  assert_eq(test_screen_watch_startup(), 0)
}
