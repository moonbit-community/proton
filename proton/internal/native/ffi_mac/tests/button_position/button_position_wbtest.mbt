///|
test "button fixture links the native runtime" {
  @ffi.link_runtime()
}

///|
extern "C" fn button_layout_test(overlay : Int) -> Int = "proton_test_button_position"

///|
test "macOS overlay positions survive layout and restore the system defaults" {
  let result = button_layout_test(1)
  // The C fixture uses __APPLE__; MoonBit C only distinguishes Windows.
  guard result != -1 else { return }
  assert_eq(result, 0)
}

///|
test "macOS default titlebars ignore custom positions" {
  let result = button_layout_test(0)
  guard result != -1 else { return }
  assert_eq(result, 0)
}
