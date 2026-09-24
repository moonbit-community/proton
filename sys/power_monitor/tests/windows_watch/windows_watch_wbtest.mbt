///|
#cfg(platform="windows")
extern "C" fn registration_failure_test(stage : Int) -> Int = "proton_test_power_registration_failure"

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
