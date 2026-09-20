# Sync And Async Extensions

Shows sync and async command-extension metadata installed through the same
`.capability(...)` API.

The source-built native route exposes `window.__MoonBit__.core.invokeOp(...)` and injects
high-level `window.__MoonBit__.math.double(...)` and
`window.__MoonBit__.add.slowAdd(...)` proxies for inline HTML.

Build:

```sh
moon -C examples build 39_sync_async_extensions --target native
```
