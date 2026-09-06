///|
test "desktop capturer extension metadata" {
  assert_eq(capability().id(), "moonbit-community/proton-desktop-capturer")
  assert_eq(capability().command_spec().js_namespace(), "desktopCapturer")
  assert_eq(capability().command_spec().op_names(), [
    "ext:desktopCapturer/getSources",
  ])
}

///|
test "desktop capturer contract documents optional thumbnails" {
  let request = @desktop_capturer_contract.GetSourcesRequest::{
    types: ["screen", "window"],
    thumbnail_width: Some(320),
    thumbnail_height: Some(200),
  }
  assert_eq(request.types.length(), 2)
  assert_eq(request.thumbnail_width, Some(320))
  assert_eq(request.thumbnail_height, Some(200))
}
