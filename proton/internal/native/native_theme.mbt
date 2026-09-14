///|
/// Reports the operating system appearance as a
/// `(dark_colors, high_contrast_colors)` pair.
///
/// The query is window independent and can run before a session exists.
pub fn native_theme_query() -> (Bool, Bool) raise NativeError {
  let dark_colors = Ref(0)
  let high_contrast_colors = Ref(0)
  check_status(
    @native_ffi.proton_native_theme_query_ffi(dark_colors, high_contrast_colors),
  )
  (dark_colors.val != 0, high_contrast_colors.val != 0)
}
