# App Commands

Hand-written Proton command-extension bridge smoke.

This example exercises the current native DLL bridge route:
`window.__MoonBit__.core.invokeOp(...)` calls registered MoonBit command
handlers through the `proton_*` C ABI request/response queue.

Run:

```sh
moon -C examples run 41_app_commands --target native
```
