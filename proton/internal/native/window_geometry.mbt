///|
/// Converts logical frame lengths to the units used by native screen positions.
/// Windows screen/work-area rectangles remain physical pixels; monitor origins
/// cannot be divided by the current window's DPI in a mixed-DPI desktop.
#cfg(platform="windows")
pub fn window_size_in_screen_coordinates(
  width : Int,
  height : Int,
  scale_factor_percent : Int,
) -> (Int, Int) {
  (
    ((width.to_int64() * scale_factor_percent.to_int64() + 50L) / 100L).to_int(),
    ((height.to_int64() * scale_factor_percent.to_int64() + 50L) / 100L).to_int(),
  )
}

///|
#cfg(not(platform="windows"))
pub fn window_size_in_screen_coordinates(
  width : Int,
  height : Int,
  _ : Int,
) -> (Int, Int) {
  (width, height)
}
