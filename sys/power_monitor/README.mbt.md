# proton_power_monitor

Native power and idle state queries for MoonBit on Windows, Linux, and macOS.

On Linux, building requires the `dbus-1` development headers and `pkg-config`.
The runtime loads libdbus optionally; without it or a reachable system bus,
starting the event watcher raises `BackendUnavailable`. Queries remain usable.
Each watcher owns its D-Bus connection and releases it when stopped. A failed
start can be retried; disconnected watchers must be started again explicitly.

The Linux watch regression test requires `dbus-daemon` and `dbus-send`. It uses
an isolated bus and does not send signals to the host system bus.
