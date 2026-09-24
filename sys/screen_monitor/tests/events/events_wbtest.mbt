///|
extern "C" fn test_screen_event_snapshots() -> Int = "proton_test_screen_event_snapshots"

///|
test "native screen queue retains removed and changed display snapshots" {
  // A value-level FFI call pulls native_common.o from the production archive
  // before the test archive is scanned by one-pass linkers.
  let monitor = @proton_screen_monitor.ScreenMonitor()
  defer monitor.destroy()
  assert_eq(test_screen_event_snapshots(), 1)
}
