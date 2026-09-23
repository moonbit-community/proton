///|
test "system preferences fixture links the native runtime" {
  @ffi.link_runtime()
}

///|
#cfg(platform="windows")
extern "C" fn consent_test() -> Int = "proton_test_desktop_media_consent"

///|
#cfg(platform="windows")
test "desktop media consent respects global deny and missing value fallbacks" {
  assert_eq(consent_test(), 0)
}
