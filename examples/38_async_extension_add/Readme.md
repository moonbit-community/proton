# Async Extension Add

Async command-extension example.

The app exposes `window.__MoonBit__.add.slowAdd(...)`. The command handler runs
in the user process; the framework process owns the WebView and bridge.

Run:

```sh
moon -C examples run 38_async_extension_add --target native
```
