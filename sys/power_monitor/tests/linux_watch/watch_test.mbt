///|
#cfg(platform="linux")
extern "C" fn watch_lifecycle_test() -> Int32 = "proton_test_power_watch_lifecycle"

///|
#cfg(platform="linux")
test "Linux power watch receives real D-Bus signals and can recover after failure" {
  assert_eq(watch_lifecycle_test(), 0)
}
