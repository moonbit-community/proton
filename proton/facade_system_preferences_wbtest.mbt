///|
test "system accent color and animation settings answer on this platform" {
  let accent = system_accent_color()
  assert_true(accent.length() == 0 || accent.length() == 8)
  assert_eq(system_animation_settings(), system_animation_settings())
}

///|
test "media access kinds map to their platform label" {
  assert_eq(MediaAccessKind::Microphone.label(), "microphone")
  assert_eq(MediaAccessKind::Camera.label(), "camera")
  assert_eq(MediaAccessKind::Screen.label(), "screen")
}

///|
test "system preference errors name the failing query" {
  let error = SystemPreferencesUnavailable(
    query="system camera access status",
    status=-8,
    detail="not available",
  )
  assert_eq(
    error.message(),
    "cannot read system camera access status (-8): not available",
  )
}
