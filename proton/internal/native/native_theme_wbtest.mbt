///|
test "native theme query works without a window and is stable" {
  let first = Some(native_theme_query()) catch { _ => None }
  let second = Some(native_theme_query()) catch { _ => None }
  assert_true(first != None)
  assert_eq(first, second)
}
