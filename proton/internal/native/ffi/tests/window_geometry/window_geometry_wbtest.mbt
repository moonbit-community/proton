///|
test "geometry fixture links the native runtime" {
  @ffi.link_runtime()
}

///|
#cfg(platform="windows")
extern "C" fn conversion_test() -> Int = "proton_test_window_dpi_conversion"

///|
#cfg(platform="windows")
extern "C" fn placement_test() -> Int = "proton_test_window_initial_placement"

///|
#cfg(platform="windows")
extern "C" fn tracking_size_test() -> Int = "proton_test_window_tracking_sizes"

///|
#cfg(platform="windows")
extern "C" fn native_size_test(overlay : Int) -> Int = "proton_test_window_native_sizes"

///|
#cfg(platform="windows")
extern "C" fn dpi_change_test() -> Int = "proton_test_window_dpi_change"

///|
#cfg(platform="windows")
test "Windows sizes round trip at 100, 150, and 250 percent" {
  assert_eq(conversion_test(), 0)
}

///|
#cfg(platform="windows")
test "initial placement fits the work area and respects explicit size hints" {
  assert_eq(placement_test(), 0)
}

///|
#cfg(platform="windows")
test "tracking sizes scale fixed, minimum, and maximum hints" {
  assert_eq(tracking_size_test(), 0)
}

///|
#cfg(platform="windows")
test "native window frame and content sizes use logical pixels" {
  assert_eq(native_size_test(0), 0)
}

///|
#cfg(platform="windows")
test "overlay content sizing measures the actual non-client area" {
  assert_eq(native_size_test(1), 0)
}

///|
#cfg(platform="windows")
test "a DPI change adopts the suggested frame without rescaling it" {
  assert_eq(dpi_change_test(), 0)
}
