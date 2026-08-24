# proton_screen_monitor

Native screen and display queries plus hot-plug events for MoonBit on Windows,
Linux, and macOS.

The module mirrors Electron's `screen` module:

- `ScreenMonitor::displays()` — `screen.getAllDisplays()`
- `ScreenMonitor::primary_display()` — `screen.getPrimaryDisplay()`
- `ScreenMonitor::display_nearest_point(x, y)` — `screen.getDisplayNearestPoint(...)`
- `ScreenMonitor::cursor_point()` — `screen.getCursorScreenPoint()`
- `DisplayAdded` / `DisplayRemoved` / `DisplayMetricsChanged` events —
  `screen.on('display-added' | 'display-removed' | 'display-metrics-changed')`

Coordinates are physical pixels in a top-left origin. On Linux the backend uses
X11 + RandR; a Wayland-only session reports `BackendUnavailable` for watching
while polling queries remain available through XWayland when present. The
module is published on Proton's shared workspace version.
