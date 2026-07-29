///|
/// Creates a synthetic guard for white-box testing of MoonBit-side error paths.
#borrow(last_error)
extern "C" fn native_test_guard_make(
  active : Bool,
  status : Int,
  last_error : Bytes,
  scope : Int,
) -> Guard = "moonbit_keepawake_test_guard_make"

///|
test "normalize_reason trims surrounding whitespace" {
  assert_eq(normalize_reason("  writing backups  "), "writing backups")
  assert_eq(normalize_reason("   "), default_reason)
}

///|
test "normalized reasons convert to null-terminated c strings" {
  let c_reason = @ffi.to_cstr(normalize_reason("  writing backups  "))
  assert_eq(@ffi.from_cstr(c_reason), "writing backups")
  assert_eq(c_reason[c_reason.length() - 1], 0)
}

///|
test "raise_native_error decodes backend-unavailable details" {
  let result : Result[Unit, Error] = try? raise_native_error(
    status=native_status_backend_unavailable,
    operation="acquire",
    detail=@utf8.encode("systemd-inhibit was not found"),
  )
  guard result
    is Err(BackendUnavailable(detail="systemd-inhibit was not found")) else {
    fail("expected a decoded backend-unavailable error")
  }
}

///|
test "raise_native_error uses fallback detail for empty payloads" {
  let result : Result[Unit, Error] = try? raise_native_error(
    status=999,
    operation="release",
    detail=b"",
  )
  guard result
    is Err(
      OperationFailed(
        operation="release",
        detail="The native backend did not provide extra details."
      )
    ) else {
    fail("expected an operation failure with fallback detail")
  }
}

///|
test "finish_acquire raises synthetic backend failures" {
  let handle = native_test_guard_make(
    false,
    native_status_backend_unavailable,
    @ffi.to_cstr("synthetic acquire failure"),
    Scope::PreventSystemSleep.native_code(),
  )
  let result : Result[Guard, Error] = try? finish_acquire(handle)
  guard result is Err(BackendUnavailable(detail="synthetic acquire failure")) else {
    fail("expected the synthetic acquire failure to surface")
  }
}

///|
test "finish_release raises release failures" {
  let result : Result[Unit, Error] = try? finish_release(
    native_status_operation_failed,
    @utf8.encode("synthetic release failure"),
  )
  guard result
    is Err(
      OperationFailed(operation="release", detail="synthetic release failure")
    ) else {
    fail("expected the release failure to surface")
  }
}

///|
test "run_with_cleanup returns action result after cleanup" {
  let mut cleanup_calls = 0
  let result : Result[String, Error] = try? run_with_cleanup(
    () => "kept awake",
    () => cleanup_calls += 1,
  )
  assert_eq(cleanup_calls, 1)
  guard result is Ok("kept awake") else {
    fail("expected the action result to be returned")
  }
}

///|
test "run_with_cleanup preserves action error and suppresses cleanup error" {
  let mut cleanup_calls = 0
  let result : Result[Int, Error] = try? run_with_cleanup(
    fn() -> Int raise { raise BackendUnavailable(detail="action failed") },
    fn() -> Unit raise {
      cleanup_calls += 1
      raise OperationFailed(operation="release", detail="cleanup failed")
    },
  )
  assert_eq(cleanup_calls, 1)
  guard result is Err(BackendUnavailable(detail="action failed")) else {
    fail("expected the original action error")
  }
}

///|
test "scope codes round-trip" {
  let scopes : Array[Scope] = [
    Scope::PreventSystemSleep,
    Scope::PreventDisplaySleep,
    Scope::PreventSystemAndDisplaySleep,
  ]
  for scope in scopes {
    assert_eq(scope_from_native_code(scope.native_code()), scope)
  }
}

///|
test "classify_native_error keeps backend-unavailable distinct" {
  guard classify_native_error(
      status=native_status_backend_unavailable,
      operation="acquire",
      detail="systemd-inhibit was not found",
    )
    is BackendUnavailable(detail="systemd-inhibit was not found") else {
    fail("expected a backend-unavailable error")
  }
}

///|
test "classify_native_error maps operational failures" {
  guard classify_native_error(
      status=native_status_operation_failed,
      operation="release",
      detail="release failed",
    )
    is OperationFailed(operation="release", detail="release failed") else {
    fail("expected an operation-failed error")
  }
}

///|
test "error show output stays readable" {
  assert_eq(
    BackendUnavailable(detail="missing backend").to_string(),
    "BackendUnavailable(detail=\"missing backend\")",
  )
  assert_eq(
    OperationFailed(operation="release", detail="failed").to_string(),
    "OperationFailed(operation=\"release\", detail=\"failed\")",
  )
}
