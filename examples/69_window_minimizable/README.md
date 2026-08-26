# Window Minimizable

Manual review for Electron-style `WindowHandle::set_minimizable`.

```sh
moon -C examples run 69_window_minimizable --target native
```

Toggle the controls, then inspect the native title bar and try the operating
system's minimize shortcut or menu. macOS and Windows update the native
minimize control; Linux follows Electron as a successful no-op. Headless
runtimes report unsupported.
