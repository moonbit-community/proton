///|
test "clipboard text length handles empty clipboard reply" {
  guard text_length(None) is None else {
    fail("expected missing text to have no length")
  }
  guard text_length(Some("moon")) is Some(4) else {
    fail("expected text length")
  }
}

///|
test "clipboard metadata constants match generated app command extension" {
  assert_eq(extension().id(), "justjavac/proton-clipboard")
  let spec = extension().command_spec()
  assert_eq(spec.js_namespace(), "clipboard")
  assert_eq(spec.op_names(), [
    "ext:clipboard/readText", "ext:clipboard/writeText",
  ])
}
