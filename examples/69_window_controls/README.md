# Window Controls

Manual review for Electron-style `WindowHandle::set_minimizable`,
`WindowHandle::set_maximizable`, and `WindowHandle::set_closable`.

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

macOS and Windows update native controls. Linux follows Electron and treats
these capability setters as successful no-ops. Headless runtimes report
unsupported.
