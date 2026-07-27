///|
test "notification requires a body" {
  let error = try ensure_body("") catch {
    error => error
  } noraise {
    _ => abort("expected empty notification body error")
  }
  inspect(error.message(), content="notification body must not be empty")
  assert_eq(ensure_body("ready"), "ready")
}
