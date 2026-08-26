# Window Movable

This is a manual review example for Proton's Electron-style
`WindowHandle::set_movable` API.

Run it with:

```sh
moon -C examples run 64_window_movable --target native
```

Review the native window frame:

1. Drag the native title bar and confirm the window starts movable.
2. Choose **Disable manual movement**, then repeat the same title-bar gesture.
   The frame should stay fixed on macOS and Windows.
3. While movement is disabled, choose **Programmatic nudge** and **Center
   window**. Both operations should still move the frame.
4. Choose **Enable manual movement** and confirm title-bar dragging works again
   without restarting the process.
5. Watch the reported position to distinguish a blocked manual drag from a
   successful programmatic move.

Platform details:

- macOS calls `NSWindow.setMovable` on the live window.
- Windows blocks interactive movement in `WM_MOVING`; programmatic placement
  through `SetWindowPos` remains available.
- Linux follows Electron's intentional no-op behavior. Calls succeed, but the
  desktop window manager can still move the window.
- Headless runtimes report unsupported because they have no native frame.
