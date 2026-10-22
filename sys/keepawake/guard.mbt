///|
/// The reason used when callers supply an empty or whitespace-only reason.
pub let default_reason : String = "MoonBit keepawake request"

///|
priv enum GuardBackend {
  Native(NativeGuard)
  Linux(@process.Process, @process.WriteToProcess)
}

///|
/// A keep-awake request owned by the task group passed to `acquire`.
/// Explicit release ends it early; leaving the group also releases it.
pub struct Guard {
  priv backend : GuardBackend
  priv requested_scope : Scope
  priv mut released : Bool
}

///|
/// Acquires inhibition before returning. The task group owns its lifetime.
/// Linux waits asynchronously for systemd-inhibit to acquire the lock; missing
/// or failing backends raise KeepAwakeError. Cancellation stops and reaps the
/// helper. Callers can impose a startup deadline with `@async.with_timeout`.
/// macOS and Windows retain their native power assertions. On Windows, acquire
/// and release must run on the same OS thread.
pub async fn[G] acquire(
  group : @async.TaskGroup[G],
  reason~ : String = default_reason,
  scope~ : Scope = Scope::PreventSystemSleep,
) -> Guard raise KeepAwakeError {
  if @async.platform is Linux {
    return acquire_linux(
      group,
      "systemd-inhibit",
      normalize_reason(reason),
      scope,
    )
  }
  let handle = finish_acquire(
    native_guard_create(
      @ffi.to_cstr(normalize_reason(reason)),
      scope.native_code(),
    ),
  )
  let keep_guard = Guard::{
    backend: Native(handle),
    requested_scope: scope,
    released: false,
  }
  group.add_defer(() => keep_guard.release())
  keep_guard
}

///|
async fn[G] acquire_linux(
  group : @async.TaskGroup[G],
  tool : String,
  reason : String,
  scope : Scope,
) -> Guard raise KeepAwakeError {
  let what = match scope {
    PreventSystemSleep => "sleep"
    PreventDisplaySleep => "idle"
    PreventSystemAndDisplaySleep => "idle:sleep"
  }
  try {
    let (stdin, writer) = @process.write_to_process()
    let mut acquired = false
    defer (if !acquired { writer.close() })
    let (reader, stdout) = @process.read_from_process()
    defer reader.close()
    let child = @process.spawn(
      group,
      tool,
      [
        "--what", what, "--mode", "block", "--why", reason, "/bin/sh", "-c", "printf 'ready\\n'; exec /bin/cat >/dev/null",
      ],
      stdin~,
      stdout~,
      no_wait=true,
      cancel_handler=@process.hard_cancel(),
    )
    let keep_guard = Guard::{
      backend: Linux(child, writer),
      requested_scope: scope,
      released: false,
    }
    defer (if !acquired { keep_guard.release() })
    // systemd-inhibit runs our command only after acquiring the lock.
    match reader.read_until("\n") {
      Some("ready") => ()
      None => {
        let status = child.wait()
        raise OperationFailed(
          operation="acquire",
          detail="systemd-inhibit exited before readiness (status \{status})",
        )
      }
      Some(_) =>
        raise OperationFailed(
          operation="acquire",
          detail="invalid systemd-inhibit readiness acknowledgement",
        )
    }
    if child.try_wait() is Some(status) {
      raise OperationFailed(
        operation="acquire",
        detail="systemd-inhibit exited at readiness (status \{status})",
      )
    }
    group.add_defer(() => keep_guard.release())
    acquired = true
    keep_guard
  } catch {
    BackendUnavailable(..) as error => raise error
    OperationFailed(..) as error => raise error
    @os_error.OSError(_) as error if error.is_ENOENT() =>
      raise BackendUnavailable(detail=error.to_string())
    error =>
      raise OperationFailed(operation="acquire", detail=error.to_string())
  }
}

///|
/// Runs asynchronous work after acquiring inhibition, then releases it on
/// return, error or cancellation. On Linux, unexpected helper exit fails this
/// scope and cancels the work. No manual task group or guard is needed.
pub async fn[T] with_keepawake(
  action : async () -> T,
  reason~ : String = default_reason,
  scope~ : Scope = Scope::PreventSystemSleep,
) -> T {
  @async.with_task_group(group => {
    let keep_guard = acquire(group, reason~, scope~)
    keep_guard.with_action(action)
  })
}

///|
async fn[T] Guard::with_action(self : Guard, action : async () -> T) -> T {
  run_with_cleanup(
    () => {
      match self.backend {
        Native(_) => action()
        Linux(child, _) =>
          @async.any([
            action,
            () => {
              let status = child.wait()
              raise OperationFailed(
                operation="watch",
                detail="systemd-inhibit exited while inhibition was required (status \{status})",
              )
            },
          ])
      }
    },
    () => self.release(),
  )
}

///|
/// Reports whether inhibition remains active. A Linux helper that has exited
/// is inactive even if `release` has not been called. This is a point-in-time
/// observation; `with_keepawake` also monitors helper exit during scoped work.
pub fn Guard::active(self : Guard) -> Bool {
  if self.released {
    return false
  }
  match self.backend {
    Native(handle) => native_guard_is_active(handle)
    Linux(child, _) => (child.try_wait() catch { _ => Some(-1) }) is None
  }
}

///|
/// Returns the requested scope.
pub fn Guard::scope(self : Guard) -> Scope {
  match self.backend {
    Native(handle) => scope_from_native_code(native_guard_scope_code(handle))
    Linux(_, _) => self.requested_scope
  }
}

///|
/// Releases inhibition and awaits Linux helper cleanup without blocking the
/// event loop. Safe to call repeatedly and during cancellation cleanup.
pub async fn Guard::release(
  self : Guard,
) -> Unit raise KeepAwakeError + nocancel {
  match self.backend {
    Native(handle) =>
      if !self.released {
        finish_release(
          native_guard_release(handle),
          native_guard_last_error(handle),
        )
        self.released = true
      }
    Linux(child, writer) => {
      self.released = true
      writer.close()
      child.cancel()
      @async.protect_from_cancel(() => ignore(child.wait())) catch {
        error =>
          raise OperationFailed(operation="release", detail=error.to_string())
      }
    }
  }
}
