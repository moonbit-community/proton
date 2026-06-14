///|
test "AppEntry::Asset reports CEF root backend as unsupported" {
  match asset_origin_unsupported_backend_error("cef") {
    Some(error) =>
      assert_eq(
        error, "AppEntry::Asset requires the Windows WebView2 backend; current backend is cef",
      )
    None => fail("expected CEF backend to be unsupported")
  }
  assert_true(asset_origin_unsupported_backend_error("webview2") is None)
}
