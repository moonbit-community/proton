///|
test "shell target validation rejects empty strings" {
  @debug.assert_eq(
    validate_target("", "shell.open target"),
    Err("shell.open target must not be empty"),
  )
  @debug.assert_eq(
    validate_target("https://example.com", "shell.open target"),
    Ok("https://example.com"),
  )
}
