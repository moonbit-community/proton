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
