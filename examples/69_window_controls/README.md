# Window Controls

Manual review for Electron-style `WindowHandle::set_minimizable` and
`WindowHandle::set_maximizable`.

```sh
moon -C examples run 69_window_controls --target native
```

Toggle each combination and inspect the native title bar. Confirm that
disabling minimize or maximize affects only that button, while ordinary edge
resizing remains independent. macOS and Windows update native controls; Linux
follows Electron as a successful no-op. Headless runtimes report unsupported.
