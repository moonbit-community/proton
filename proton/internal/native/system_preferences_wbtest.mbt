///|
/// PROTON_ERR_UNSUPPORTED, the status a platform reports for a query it does
/// not own. The tests assert the platform matrix, so they name it directly
/// instead of letting the facade fold it into its error type.
let system_preferences_unsupported = -8

///|
test "system accent color is stable and reports RGBA digits or nothing" {
  let accent = system_accent_color()
  assert_eq(accent, system_accent_color())
  assert_true(accent.length() == 0 || accent.length() == 8)
}

///|
test "system animation settings are stable without a session" {
  assert_eq(system_animation_settings(), system_animation_settings())
}

///|
test "media access answers on Windows and macOS and fails on Linux" {
  let platform = runtime_platform_id()
  let status = system_media_access_status(Microphone) catch {
    error => {
      assert_true(platform.has_prefix("linux-"))
      assert_eq(error.status(), system_preferences_unsupported)
      return
    }
  }
  assert_false(platform.has_prefix("linux-"))
  // Both consent stores always resolve to a concrete state, never to the
  // fallback for a status the platform could not report.
  assert_true(status != Unknown)
}

///|
test "Windows reports screen capture access as granted" {
  if runtime_platform_id().has_prefix("win32-") {
    assert_eq(system_media_access_status(Screen), Granted)
  }
}

///|
test "accessibility client trust fails when the platform does not own it" {
  let platform = runtime_platform_id()
  let trusted = system_accessibility_client_trusted(false) catch {
    error => {
      assert_false(platform.has_prefix("darwin-"))
      assert_eq(error.status(), system_preferences_unsupported)
      return
    }
  }
  assert_true(platform.has_prefix("darwin-"))
  // A freshly built test binary is not a registered accessibility client.
  assert_false(trusted)
}
