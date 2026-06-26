# Event Broadcast

Native DLL bridge example for command-extension event broadcast.

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
node scripts/e2e_bridge_smoke.mjs 40_event_broadcast
```
