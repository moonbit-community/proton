# Event Broadcast

Source-built command-extension example for event broadcast.

The page calls `window.__MoonBit__.ticker.start(payload)` and subscribes with
`window.__MoonBit__.ticker.on("tick", listener)` / `ticker.on("done", listener)`.
MoonBit emits those events with `context.emit(...)` from the async command
handler.

Build:

```sh
moon -C examples build 40_event_broadcast --target native
```

E2E:

```sh
moon -C e2e test -p moonbit-community/proton/e2e/test --target native \
  --no-parallelize --filter '*40_event_broadcast*'
```
