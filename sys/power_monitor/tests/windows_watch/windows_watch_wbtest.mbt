///|
#cfg(platform="windows")
extern "C" fn registration_failure_test(stage : Int32) -> Int32 = "proton_test_power_registration_failure"

///|
#cfg(platform="windows")
test "Windows session registration failure reaches the public native error boundary" {
  assert_eq(registration_failure_test(1), 0)
}

///|
#cfg(platform="windows")
test "Windows power registration failure rolls back the session registration" {
  assert_eq(registration_failure_test(2), 0)
}

///|
#cfg(platform="windows")
extern "C" fn power_source_notifications_test() -> Int32 = "proton_test_power_source_notifications"

///|
#cfg(platform="windows")
test "Windows power notifications distinguish AC, battery, and unsupported sources" {
  assert_eq(power_source_notifications_test(), 0)
}

///|
#cfg(platform="windows")
extern "C" fn idle_tick_wraparound_test() -> Int32 = "proton_test_idle_tick_wraparound"

///|
#cfg(platform="windows")
test "Windows idle queries use the last-input counter width across uptime wraps" {
  assert_eq(idle_tick_wraparound_test(), 0)
}
