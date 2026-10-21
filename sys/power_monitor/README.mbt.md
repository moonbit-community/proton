# proton_power_monitor

Native power and idle state queries for MoonBit on Windows, Linux, and macOS.

`PowerMonitor::with_watching` owns event watching for the duration of its async
callback. The callback begins only after registration succeeds. Returning,
raising, or cancelling the scope stops the watcher and waits for cleanup.
Cancel its owning task to stop watching; there is no separate start/stop queue.
A second scope on the same monitor raises `OperationFailed` immediately.

```moonbit nocheck
let monitor = @power_monitor.PowerMonitor()
defer monitor.destroy()
monitor.with_watching(() => {
  // Use monitor.drain_events() from the application's event loop.
  // Keep this scope alive until the owning task is cancelled.
  @async.pause()
})
```

`destroy()` is synchronous and accepts only an idle monitor. End its watching
scope first. Idle and power-source queries do not start event watching.

On Linux, building requires `pkg-config` and GIO development headers
(`libglib2.0-dev` on Ubuntu). GIO is loaded dynamically and remains optional at
runtime. A missing library or unavailable system bus raises `BackendUnavailable`;
queries remain usable. Connection establishment, authentication and subscription
are asynchronous and cancellable, with a five-second deadline for the whole
startup. A disconnected bus fails the scope and cancels its callback. A new
scope can retry after failure; there is no automatic reconnection.

The Proton extension owns the scope in an application task. `watch_status()`
reports `Starting`, `Watching`, or `Unavailable(detail)`; application teardown
resets it to `Stopped`.

The Linux regression tests require `dbus-daemon` and `dbus-send`. They use an
isolated bus and loopback listener, never the host system bus. They cover paused
startup, timeout, cancellation during transport establishment, concurrent-scope
rejection, partial registration rollback, signals, disconnection and restart.
