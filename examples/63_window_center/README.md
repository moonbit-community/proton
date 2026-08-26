# Window Center

This is a manual review example for Proton's Electron-style
`WindowHandle::center` API.

Run it with:

```sh
moon -C examples run 63_window_center --target native
```

Review the native window frame:

1. Move and resize the window so its position and size are easy to recognize.
2. Click **Center window** and confirm the frame moves to the center of the
   current monitor's work area, not the full monitor bounds.
3. Move the window to another display, then center it again. The reported
   monitor and work-area coordinates should change with the window.
4. Resize the window, center it again, and confirm the new frame size is
   preserved while only the position changes.
5. On Windows with display scaling above 100%, confirm the native frame and
   reported coordinates remain consistent.

The API uses the existing native window state snapshot and position operation;
no second runtime path or platform-specific centering ABI is introduced.
Headless runtimes cannot be centered because they have no native frame.
