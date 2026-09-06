///|
test "desktop capturer extension metadata" {
  assert_eq(capability().id(), "moonbit-community/proton-desktop-capturer")
  assert_eq(capability().command_spec().js_namespace(), "desktopCapturer")
  assert_eq(capability().command_spec().op_names(), [
    "ext:desktopCapturer/getSources",
  ])
}
