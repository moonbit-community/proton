///|
/// Sets the application-level theme source: 0 system, 1 light, 2 dark.
pub fn native_theme_set_source(source : Int) -> Unit raise NativeError {
  check_status(@native_ffi.proton_native_theme_set_source_ffi(source))
}

///|
/// Reports the operating system appearance as a
/// `(dark_colors, high_contrast_colors, source)` triple.
///
/// The query is window independent and can run before a session exists.
pub fn native_theme_query() -> (Bool, Bool, Int) raise NativeError {
  let dark_colors = Ref(0)
  let high_contrast_colors = Ref(0)
  let source = Ref(0)
  check_status(
    @native_ffi.proton_native_theme_query_ffi(
      dark_colors, high_contrast_colors, source,
    ),
  )
  (dark_colors.val != 0, high_contrast_colors.val != 0, source.val)
}
