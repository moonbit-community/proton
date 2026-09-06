# desktopCapturer

The `desktopCapturer` extension exposes Electron-compatible `getSources` data
through Proton's typed command bridge.

Supported source types are `screen` and `window`:

- Windows enumerates visible titled windows and captures requested window
  thumbnails with the native GDI backend.
- macOS enumerates displays and captures requested screen thumbnails through
  CoreGraphics when the process has screen-recording permission.
- Linux enumerates displays through the existing X11/RandR monitor backend.
  Screen and window thumbnails are currently unavailable and are returned as
  `null`; the source geometry remains usable.

`thumbnail_width` and `thumbnail_height` must be supplied together, must be
positive, and may not exceed 4096. Omitting either dimension disables thumbnail
capture. A missing thumbnail indicates that the platform backend or required
operating-system permission is unavailable; it is not a placeholder image.
