# Async Extension Add

Async command-extension metadata example.

This package registers an async command extension through `.extension(...)`.
The native DLL route exposes `window.__MoonBit__.core.invokeOp(...)` and injects
the high-level `window.__MoonBit__.add.slowAdd(...)` proxy for inline HTML.

Build:

```sh
moon -C examples build 38_async_extension_add --target native
```

E2E smoke:

```sh
moon -C e2e test -p justjavac/proton/e2e/test --target native \
  --no-parallelize --filter '*38_async_extension_add*'
```
