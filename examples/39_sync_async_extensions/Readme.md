# Sync And Async Extensions

Shows sync and async command-extension metadata installed through the same
`.extension(...)` API.

The native DLL route exposes `window.__MoonBit__.core.invokeOp(...)` and injects
high-level `window.__MoonBit__.math.double(...)` and
`window.__MoonBit__.add.slowAdd(...)` proxies for inline HTML.

Build:

```sh
moon -C examples build 39_sync_async_extensions --target native
```

E2E smoke:

```sh
node scripts/e2e_bridge_smoke.mjs 39_sync_async_extensions
```
