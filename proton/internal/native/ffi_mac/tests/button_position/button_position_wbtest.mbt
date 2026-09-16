///|
test "button fixture links the native runtime" {
  @ffi.link_runtime()
}

///|
#cfg(all(not(platform="linux"), not(platform="windows")))
extern "C" fn button_layout_test(overlay : Int) -> Int = "proton_test_button_position"

///|
#cfg(all(not(platform="linux"), not(platform="windows")))
test "macOS overlay positions survive layout and restore the system defaults" {
  assert_eq(button_layout_test(1), 0)
}

///|
#cfg(all(not(platform="linux"), not(platform="windows")))
test "macOS default titlebars ignore custom positions" {
  assert_eq(button_layout_test(0), 0)
}
