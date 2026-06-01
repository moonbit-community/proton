# Async Extension Add

This example shows one command extension whose handler runs in the user process
and uses MoonBit `async`.

The same executable has two roles:

- framework process: opens the WebView and injects the WebSocket IPC bridge.
- command-host process: registers `examples/async-add` and handles
  `window.__MoonBit__.add.slowAdd(...)`.

`main.mbt` keeps the process split in one place. The extension logic lives in
`async_add_extension.mbt`, so adding more APIs does not make startup code harder
to read.

## Run

```sh
moon -C examples run 38_async_extension_add --target native
```

