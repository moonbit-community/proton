///|
test "native theme query works without a window and is stable" {
  let first = Some(native_theme_query()) catch { _ => None }
  let second = Some(native_theme_query()) catch { _ => None }
  assert_true(first != None)
  assert_eq(first, second)
}

///|
test "theme source override is reported by the query" {
  let applied = try {
    native_theme_set_source(2)
    true
  } catch {
    _ => false
  }
  assert_true(applied)
  let snapshot = Some(native_theme_query()) catch { _ => None }
  match snapshot {
    Some((dark_colors, _, source)) => {
      assert_true(dark_colors)
      assert_eq(source, 2)
    }
    None => fail("native theme query failed")
  }
  // Leave the process without an application-level override.
  native_theme_set_source(0) catch {
    _ => ()
  }
}

///|
test "native theme change events carry the appearance snapshot" {
  let snapshot = native_theme_snapshot(1, 0, 2)
  assert_true(snapshot.dark_colors)
  assert_false(snapshot.high_contrast_colors)
  assert_eq(snapshot.source, WindowThemePreference::Dark)
  let event = RuntimeEvent::NativeThemeChanged(snapshot)
  assert_eq(event.event_type(), "native_theme_changed")
  assert_eq(event.window_id(), None)
  assert_eq(event.native_theme_change(), Some(snapshot))
}

///|
test "native theme change snapshots normalize unreported sources" {
  let system = native_theme_snapshot(0, 0, 0)
  assert_false(system.dark_colors)
  assert_eq(system.source, WindowThemePreference::System)
  let unknown = native_theme_snapshot(1, 1, 9)
  assert_true(unknown.dark_colors)
  assert_true(unknown.high_contrast_colors)
  assert_eq(unknown.source, WindowThemePreference::System)
}

///|
test "only theme change events report a native theme snapshot" {
  assert_eq(RuntimeEvent::QuitRequested.native_theme_change(), None)
  assert_eq(
    RuntimeEvent::LaunchInput(OpenUrls(["app://settings"])).native_theme_change(),
    None,
  )
}
