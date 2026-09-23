///|
#cfg(platform="windows")
extern "C" fn view_bounds_test() -> Int = "proton_test_view_native_bounds"

///|
#cfg(platform="windows")
test "child view bounds use logical pixels on creation and relayout" {
  assert_eq(view_bounds_test(), 0)
}

///|
#cfg(platform="windows")
extern "C" fn view_caption_test() -> Int = "proton_test_view_caption_clip"

///|
#cfg(platform="windows")
test "offset views preserve caption buttons after moving and resizing" {
  assert_eq(view_caption_test(), 0)
}

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

///|
#cfg(platform="windows")
extern "C" fn titlebar_native_hit_test() -> Int = "proton_test_titlebar_native_hit_test"

///|
#cfg(platform="windows")
test "overlay hit testing keeps the whole sidebar button clickable" {
  assert_eq(titlebar_native_hit_test(), 0)
}

///|
#cfg(platform="windows")
extern "C" fn titlebar_dpi_regions_test() -> Int = "proton_test_titlebar_dpi_regions"

///|
#cfg(platform="windows")
test "titlebar button pixels and edges respect 100 through 250 percent DPI" {
  assert_eq(titlebar_dpi_regions_test(), 0)
}

///|
#cfg(platform="windows")
extern "C" fn closed_modal_collection_test() -> Int = "proton_test_closed_modal_window_collection"

///|
#cfg(platform="windows")
test "closed modal records survive collection until native destruction" {
  assert_eq(closed_modal_collection_test(), 0)
}
