///|
/// Normalizes caller-supplied reasons before they cross the FFI boundary.
fn normalize_reason(reason : String) -> String {
  let trimmed = reason.trim().to_owned()
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
  status~ : Int32,
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
fn finish_acquire(handle : NativeGuard) -> NativeGuard raise KeepAwakeError {
  if native_guard_is_active(handle) {
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
fn finish_release(status : Int32, detail : Bytes) -> Unit raise KeepAwakeError {
  if status == native_status_ok {
    ()
  } else {
    raise_native_error(status~, operation="release", detail~)
  }
}

///|
/// Runs an action and always attempts cleanup before returning or re-raising.
async fn[T] run_with_cleanup(
  action : async () -> T,
  cleanup : async () -> Unit,
) -> T {
  let value = {
    errdefer (cleanup() catch { _ => () })
    action()
  }
  cleanup()
  value
}

///|
/// Maps native backend status codes into public MoonBit errors.
fn classify_native_error(
  status~ : Int32,
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
