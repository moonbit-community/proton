# Window Attention

This is a manual review example for Proton's Electron-style
`WindowHandle::flash_frame` API.

Run it with:

```sh
moon -C examples run 60_window_attention --target native
```

Review the application attention indicator:

1. Choose **Start in 3s**, then switch to another application before the
   countdown reaches zero. The Proton attention indicator should start.
2. Activate the Proton application again. The platform should stop or clear the
   attention request automatically when the window becomes active.
3. Choose **Run for 5s**, then switch to another application. The attention
   indicator should start and stop after five seconds without activating Proton.
4. Repeat **Start in 3s** while staying in Proton. An active application should
   not visibly bounce its own Dock icon.
5. Choose **Stop** to exercise an explicit `flash_frame(false)` call. It should
   be safe when no request is active.

Platform details:

- macOS uses a critical application attention request, exposed through the
  Dock icon. `false` cancels the request started by that window.
- Windows flashes the window's taskbar button with `FlashWindowEx`; `false`
  sends `FLASHW_STOP`.
- Linux uses GTK's window urgency hint. The visible indicator depends on the
  desktop environment and window manager.
- Headless runtimes report unsupported because there is no native window to
  signal.
