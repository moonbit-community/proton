# Multiprocess MBT Backend

This example runs Lepus as two processes:

- `webview/`: owns the native window, JavaScript bridge, and WebView2 event loop.
- `backend/`: owns MoonBit command handlers and async work through
  `MbtProcessHost::run_stdio()`.

When launched by the webview process, `run_stdio()` auto-detects the local file
IPC directory passed by the transport environment. The same backend entrypoint
can still run line-delimited JSON over stdin/stdout for custom launchers. The
webview process uses `create_app_with_mbt_process(...)` and exposes:

- `app:ping`
- `app:slowAdd`
- `app:fail`

## Run

Build both executables first so the webview process can find the backend:

```sh
moon -C examples build 41_multiprocess_mbt_backend/backend --target native
moon -C examples run 41_multiprocess_mbt_backend/webview --target native
```

Or build all examples:

```sh
moon -C examples build --target native
moon -C examples run 41_multiprocess_mbt_backend/webview --target native
```
