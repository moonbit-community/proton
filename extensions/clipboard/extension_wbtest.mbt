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
  assert_eq(generated_app_command_extension().id(), "justjavac/lepus-clipboard")
  assert_eq(generated_app_command_extension().js_namespace(), "clipboard")
}
