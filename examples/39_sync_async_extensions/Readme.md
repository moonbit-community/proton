# Sync And Async Extensions

This example registers synchronous and asynchronous command extensions through
the same manifest and registry style.

- `sync_math_extension.mbt` exposes `window.__MoonBit__.math.double(...)`.
- `async_add_extension.mbt` exposes `window.__MoonBit__.add.slowAdd(...)`.

Both handlers run in the user parent process. The framework child process only
owns the WebView, the bridge script, and framework-side extensions.

## Run

```sh
moon -C examples run 39_sync_async_extensions --target native
```
