///|
test "shell target validation rejects empty strings" {
  let error = try validate_target("", "shell.open target") catch {
    error => error
  } noraise {
    _ => abort("expected empty target error")
  }
  inspect(error.message(), content="shell.open target must not be empty")
  assert_eq(
    validate_target("https://example.com", "shell.open target"),
    "https://example.com",
  )
}
