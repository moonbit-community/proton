# Sync And Async Extensions

Shows sync and async command-extension metadata installed through the same
`.expose(...)` API.

The native DLL route exposes `window.__MoonBit__.core.invokeOp(...)` and injects
high-level `window.__MoonBit__.math.double(...)` and
`window.__MoonBit__.add.slowAdd(...)` proxies for inline HTML.

Build:

```sh
moon -C examples build 39_sync_async_extensions --target native
```

E2E smoke:

```sh
moon -C e2e test -p moonbit-community/proton/e2e/test --target native \
  --no-parallelize --filter '*39_sync_async_extensions*'
```
