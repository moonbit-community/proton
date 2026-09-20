# Async Extension Add

Async command-extension metadata example.

This package installs and grants an async command extension through
`.capability(...)`.
The source-built native route exposes `window.__MoonBit__.core.invokeOp(...)` and injects
the high-level `window.__MoonBit__.add.slowAdd(...)` proxy for inline HTML.

Build:

```sh
moon -C examples build 38_async_extension_add --target native
```
