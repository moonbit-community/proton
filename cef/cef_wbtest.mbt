///|
test "cef backend advertises stable id and unavailable shim" {
  inspect(backend_id(), content="cef")
  inspect(is_available(), content="false")
  inspect(
    ensure_available(),
    content=(
      #|Err("CEF backend is not linked. Add the CEF SDK/native shim and build an app that explicitly imports justjavac/lepus_cef.")
    ),
  )
}

///|
test "cef settings keep explicit opt-in defaults" {
  let settings = CefSettings::new(debug=true, remote_debugging_port=Some(9222))
  assert_true(settings.cache_path is None)
  assert_true(settings.user_data_path is None)
  assert_true(settings.subprocess_path is None)
  guard settings.remote_debugging_port is Some(9222) else {
    fail("expected remote debugging port")
  }
  assert_true(settings.locale is None)
  assert_false(settings.sandbox)
  assert_true(settings.debug)
}

///|
test "cef runtime initialization fails clearly without native cef" {
  match CefRuntime::initialize() {
    Ok(_) => fail("expected CEF initialization to fail without native CEF")
    Err(error) =>
      assert_eq(
        error, "CefRuntime::initialize failed: CEF backend is not linked in this binary",
      )
  }
}
