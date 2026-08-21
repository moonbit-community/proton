# App Commands

Proton command-extension bridge example and native E2E fixture.

This example exercises the current source-built native bridge route:
`window.__MoonBit__.core.invokeOp(...)` calls registered MoonBit command
handlers through the `proton_*` C ABI request/response queue.

Its application implementation is shared with the MoonBit E2E suite through
the adjacent `app_commands_fixture` package, so the example and test cannot
silently drift apart.

Run:

```sh
moon -C examples run 41_app_commands --target native
```

Run its native CDP E2E probe:

```sh
moon -C e2e test -p moonbit-community/proton/e2e/test --target native \
  --no-parallelize --filter '*41_app_commands*'
```
