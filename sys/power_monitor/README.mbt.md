# proton_power_monitor

Native power and idle state queries for MoonBit on Windows, Linux, and macOS.

On Linux, building requires the `dbus-1` development headers and `pkg-config`.
The runtime loads libdbus optionally; without it or a reachable system bus,
starting the event watcher raises `BackendUnavailable`. Queries remain usable.
`start_watching()`, `stop_watching()`, and `destroy()` are asynchronous. On
Linux, waiting for bus authentication or subscription replies does not block
other tasks. Cancelling startup stops the pending request and waits for native
cleanup before propagating cancellation. `stop_watching()` also interrupts a
concurrent startup and waits for cleanup. A failed start can be retried;
disconnected watchers must be started again explicitly.

Keep cleanup in a cancellation-protected scope:

```moonbit nocheck
let monitor = @power_monitor.PowerMonitor()
defer @async.protect_from_cancel(() => monitor.destroy())
monitor.start_watching()
// Consume monitor.drain_events() using the application's event loop.
```

Idle and power-source queries do not start event watching. The Proton extension
starts its watcher in an application-owned task and reports `Starting`,
`Watching`, or `Unavailable(detail)` through `watch_status()`. Application
teardown stops the watcher and resets the status to `Stopped`.

The Linux watch regression test requires `dbus-daemon` and `dbus-send`. It uses
an isolated bus and does not send signals to the host system bus.
