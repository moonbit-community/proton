///|
test "dialog level maps to native code" {
  assert_eq(level_to_int(None), 0)
  assert_eq(level_to_int(Some("warning")), 1)
  assert_eq(level_to_int(Some("error")), 2)
}

///|
test "dialog empty wide string becomes None path" {
  @debug.assert_eq(optional_path_from_wstr(@ffi.to_wstr("")), None)
  @debug.assert_eq(
    optional_path_from_wstr(@ffi.to_wstr("demo.txt")),
    Some("demo.txt"),
  )
}

///|
test "dialog metadata constants match generated app command extension" {
  assert_eq(extension().id(), "justjavac/proton-dialog")
  assert_eq(extension().command_spec().unwrap().js_namespace(), "dialog")
}
