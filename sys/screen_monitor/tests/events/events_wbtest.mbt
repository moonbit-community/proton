///|
extern "C" fn test_screen_event_snapshots() -> Int = "proton_test_screen_event_snapshots"

///|
test "native screen queue retains removed and changed display snapshots" {
  // Keep the production package linked, including its queue implementation.
  let _ : @proton_screen_monitor.ScreenMonitor? = None
  assert_eq(test_screen_event_snapshots(), 1)
}
