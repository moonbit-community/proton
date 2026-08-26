# Window Maximizable

Manual review for Electron-style `WindowHandle::set_maximizable`.

```sh
moon -C examples run 70_window_maximizable --target native
```

Disable maximize, then inspect the native title bar and try the operating
system's maximize action. Confirm ordinary edge resizing still works. Enable
maximize and confirm the native action returns. macOS and Windows update the
native maximize/zoom control; Linux follows Electron as a successful no-op.
Headless runtimes report unsupported.
