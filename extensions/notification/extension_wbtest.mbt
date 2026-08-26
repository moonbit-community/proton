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

///|
test "notification badge count is absolute and non-negative" {
  assert_eq(ensure_badge_count(0), 0)
  assert_eq(ensure_badge_count(3), 3)
  let error = try ensure_badge_count(-1) catch {
    error => error
  } noraise {
    _ => abort("expected invalid notification badge count error")
  }
  inspect(
    error.message(),
    content="notification badge count must be non-negative, got -1",
  )
}
