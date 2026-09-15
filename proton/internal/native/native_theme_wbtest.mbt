///|
test "native theme query works without a window and is stable" {
  let first = native_theme_query()
  let second = native_theme_query()
  assert_eq(first, second)
}

///|
test "native theme change events carry the appearance snapshot" {
  let snapshot = native_theme_snapshot(1, 0)
  assert_true(snapshot.dark_colors)
  assert_false(snapshot.high_contrast_colors)
  let event = RuntimeEvent::NativeThemeChanged(snapshot)
  assert_eq(event.event_type(), "native_theme_changed")
  assert_eq(event.window_id(), None)
  assert_eq(event.native_theme_change(), Some(snapshot))
}

///|
test "only theme change events report a native theme snapshot" {
  assert_eq(RuntimeEvent::QuitRequested.native_theme_change(), None)
  assert_eq(
    RuntimeEvent::LaunchInput(OpenUrls(["app://settings"])).native_theme_change(),
    None,
  )
}
