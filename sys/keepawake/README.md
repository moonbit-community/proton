# moonbit-community/proton_keepawake

Native keep-awake guards for long-running work on Windows, macOS and Linux.

```sh
moon add moonbit-community/proton_keepawake
```

Import `moonbit-community/proton_keepawake` as `@keepawake`. Call from an async
context; the scoped API acquires inhibition before starting your work:

```moonbit
let result = @keepawake.with_keepawake(
  () => export_files(),
  reason="Exporting files",
  scope=@keepawake.Scope::PreventSystemSleep,
)
```

Returning, raising or cancelling ends the request and awaits cleanup. On Linux,
unexpected helper exit raises `OperationFailed` and cancels the protected work.
Use `@async.with_timeout` if acquisition or the whole operation needs a deadline.

For explicit ownership, pass a task group whose lifetime covers the work:

```moonbit
@async.with_task_group(tasks => {
  let keep_guard = @keepawake.acquire(tasks, reason="Exporting files")
  defer keep_guard.release()
  export_files()
})
```

`acquire` and `Guard::release` are async. Release is idempotent and completes
even during cancellation cleanup. Leaving the owning task group also releases
the guard; keeping a reference does not extend protection beyond that group.
`active()` is a point-in-time status query and becomes false when released or
when the Linux helper exits. `scope()` reports the requested scope.

`KeepAwakeError::BackendUnavailable` reports a missing backend;
`OperationFailed(operation~, detail~)` reports a failed acquisition, release or
loss of protection during scoped work. Blank reasons use `default_reason`.

## Platforms

- Windows uses `SetThreadExecutionState`. Acquire and release on the same OS
  thread, as with Proton's application event loop.
- macOS uses IOKit power assertions.
- Linux requires `systemd-inhibit` and a usable logind service. Acquisition waits
  asynchronously for the lock, with no fixed readiness delay. `PreventSystemSleep`
  maps to `sleep`, `PreventDisplaySleep` to logind's `idle` inhibition, and
  `PreventSystemAndDisplaySleep` to `idle:sleep`. Idle inhibition is not a
  universal guarantee against every desktop compositor's display blanking.

The Linux helper's stdin lifetime and the async task group control its lifetime.
The module does not introduce a persistent background service or a fallback
backend. Acquisition and cleanup do not block the application event loop.

## Migration

Replace synchronous `acquire(reason=...)` with async `acquire(tasks, reason=...)`.
Call `release()` from an async context and make `with_keepawake` callbacks async.
Applications using Proton's keep-awake extension retain the same frontend
`acquire`, `release` and `status` commands; the extension owns the task group.

## License

Apache-2.0
