///|
test "notification requires a body" {
  @debug.assert_eq(ensure_body(""), Err("notification body must not be empty"))
  @debug.assert_eq(ensure_body("ready"), Ok("ready"))
}
