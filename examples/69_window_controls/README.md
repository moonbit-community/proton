# Window Controls

Manual review for Electron-style `WindowHandle::set_minimizable`,
`WindowHandle::set_maximizable`, `WindowHandle::set_closable`, and
`WindowHandle::set_focusable`.
`WindowHandle::set_fullscreenable`.

```sh
moon -C examples run 69_window_controls --target native
```

1. Toggle each capability and inspect the native title bar.
2. Disable close and confirm the native close button and user close shortcut do
   not close the window.
3. Confirm disabling minimize, maximize, or close affects only that capability,
   while ordinary edge resizing remains available.
4. With close still disabled, use **Programmatic close** as the final check and
   confirm the application can still close its own window.
5. Disable focus and click the window; on macOS and Windows it should not
   become the active window. Re-enable focus before the final close check.
6. Disable fullscreenable and confirm entering fullscreen is blocked; exiting
   an already-fullscreen window remains possible.

macOS and Windows update native controls. Linux follows Electron and treats
these capability setters as successful no-ops. Headless runtimes report
unsupported.
