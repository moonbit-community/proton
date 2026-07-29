///|
/// Normalizes caller-supplied reasons before they cross the FFI boundary.
fn normalize_reason(reason : String) -> String {
  let trimmed = reason.trim().to_string()
  if trimmed is "" {
    default_reason
  } else {
    trimmed
  }
}

///|
/// Decodes a backend error payload into a readable string.
fn decode_native_detail(detail : Bytes) -> String {
  if detail.is_empty() {
    "The native backend did not provide extra details."
  } else {
    @utf8.decode_lossy(detail)
  }
}

///|
/// Raises a public keep-awake error from raw native status and detail bytes.
fn[T] raise_native_error(
  status~ : Int,
  operation~ : String,
  detail~ : Bytes,
) -> T raise KeepAwakeError {
  raise classify_native_error(
    status~,
    operation~,
    detail=decode_native_detail(detail),
  )
}

///|
/// Resolves a newly-created native guard into either a live handle or an error.
fn finish_acquire(handle : Guard) -> Guard raise KeepAwakeError {
  if handle.active() {
    handle
  } else {
    raise_native_error(
      status=native_guard_status(handle),
      operation="acquire",
      detail=native_guard_last_error(handle),
    )
  }
}

///|
/// Raises a release failure if the native backend did not report success.
fn finish_release(status : Int, detail : Bytes) -> Unit raise KeepAwakeError {
  if status == native_status_ok {
    ()
  } else {
    raise_native_error(status~, operation="release", detail~)
  }
}

///|
/// Runs an action and always attempts cleanup before returning or re-raising.
fn[T] run_with_cleanup(
  action : () -> T raise,
  cleanup : () -> Unit raise,
) -> T raise {
  try action() catch {
    err => {
      let _ : Result[Unit, Error] = try? cleanup()
      raise err
    }
  } noraise {
    value => {
      cleanup()
      value
    }
  }
}

///|
/// Maps native backend status codes into public MoonBit errors.
fn classify_native_error(
  status~ : Int,
  operation~ : String,
  detail~ : String,
) -> KeepAwakeError {
  if status == native_status_backend_unavailable {
    BackendUnavailable(detail~)
  } else if status == native_status_operation_failed {
    OperationFailed(operation~, detail~)
  } else {
    OperationFailed(operation~, detail~)
  }
}
