///|
/// The fallback reason used when callers pass an empty or whitespace-only
/// reason.
///
/// This value is intentionally readable because some native backends expose the
/// reason in system diagnostics or activity monitors. Applications can override
/// it per call when they want more task-specific text, but keeping a default
/// reason makes the simple API path ergonomic.
pub let default_reason : String = "MoonBit keepawake request"

///|
/// Acquires a keep-awake guard for the current operating system.
///
/// The returned guard activates the native inhibition immediately and keeps it
/// alive until `Guard::release` is called or the guard is reclaimed by the
/// runtime. Blank reasons are normalized to `default_reason` so callers can
/// keep call sites simple without losing readable backend diagnostics.
///
/// `reason` should describe the user-visible work being protected, such as
/// `"Exporting a large report"` or `"Downloading offline assets"`. `scope`
/// controls whether the request blocks system sleep, display sleep, or both.
///
/// Prefer `acquire` when your code naturally manages a long-lived handle. If
/// the work is already scoped to a single callback, `with_keepawake` is usually
/// more convenient because it guarantees structured release.
///
/// # Errors
///
/// Raises `KeepAwakeError::BackendUnavailable` when the current environment
/// cannot provide a usable keep-awake backend, and raises
/// `KeepAwakeError::OperationFailed` when a backend exists but the native
/// acquire step still fails.
///
/// # Example
/// ```mbt nocheck
/// let guard = @keepawake.acquire(
///   reason="Encoding a large video",
///   scope=@keepawake.Scope::PreventSystemAndDisplaySleep,
/// )
///
/// // ... perform the long-running work ...
///
/// guard.release()
/// ```
pub fn acquire(
  reason? : String = default_reason,
  scope? : Scope = Scope::PreventSystemSleep,
) -> Guard raise KeepAwakeError {
  let handle = native_guard_create(
    @ffi.to_cstr(normalize_reason(reason)),
    scope.native_code(),
  )
  finish_acquire(handle)
}

///|
/// Runs an action while a keep-awake guard is held.
///
/// This is the most ergonomic API for scoped work such as file exports, build
/// steps, or long-running synchronization tasks. The guard is released after
/// `action` finishes. If `action` raises, release is still attempted and any
/// release failure is suppressed in favor of the original error.
///
/// This helper is the best default when the keep-awake lifetime should exactly
/// match one operation. It keeps the call site small, avoids leaking a guard in
/// early-return branches, and preserves the original application error if both
/// the action and the release step fail.
///
/// `reason` and `scope` behave the same way as in `acquire`. The return value
/// of `action` is passed through unchanged.
///
/// # Errors
///
/// Raises the same `KeepAwakeError` values as `acquire`, plus any error raised
/// by `action`.
///
/// # Example
/// ```mbt nocheck
/// let summary = @keepawake.with_keepawake(
///   () => "done",
///   reason="Syncing local cache",
///   // ... perform long-running work ...
///   scope=@keepawake.Scope::PreventSystemSleep,
/// )
/// ```
pub fn[T] with_keepawake(
  action : () -> T raise?,
  reason? : String = default_reason,
  scope? : Scope = Scope::PreventSystemSleep,
) -> T raise {
  let handle = acquire(reason~, scope~)
  run_with_cleanup(fn() -> T raise { action() }, fn() -> Unit raise {
    handle.release()
  })
}

///|
/// Returns whether the underlying native inhibition is still active.
///
/// This becomes `false` after a successful call to `Guard::release`, and it is
/// also `false` for guards returned by a failed acquire attempt before the
/// error is raised to the caller.
///
/// Use this method for diagnostics, assertions, or defensive checks around
/// cleanup-heavy workflows. Most callers do not need to poll it during normal
/// operation because the guard exposes only a single lifecycle boundary:
/// active versus released.
pub fn Guard::active(self : Guard) -> Bool {
  native_guard_is_active(self)
}

///|
/// Returns the scope that was requested when the guard was created.
///
/// This is the semantic scope originally passed to `acquire` or
/// `with_keepawake`, not a platform-specific low-level flag set. It is useful
/// when code stores guards in higher-level abstractions and later wants to
/// inspect or report what kind of inhibition is currently in effect.
pub fn Guard::scope(self : Guard) -> Scope {
  scope_from_native_code(native_guard_scope_code(self))
}

///|
/// Releases the native keep-awake request.
///
/// Releasing a guard is idempotent. Calling `release` on an inactive guard is a
/// no-op. If the backend reports an unexpected release failure, this method
/// raises `KeepAwakeError::OperationFailed`.
///
/// Call this as soon as the protected work finishes when you acquired the guard
/// manually. Releasing early is preferred over waiting for runtime cleanup,
/// because explicit release makes the lifetime obvious and avoids depending on
/// garbage collection timing.
///
/// # Errors
///
/// Raises `KeepAwakeError::OperationFailed` if the backend reports that the
/// native release operation did not complete successfully.
pub fn Guard::release(self : Guard) -> Unit raise KeepAwakeError {
  let status = native_guard_release(self)
  finish_release(status, native_guard_last_error(self))
}
