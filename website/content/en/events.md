# Events

[中文](zh/events.html)

Events are typed host-to-renderer notifications with no response value. `proton_contract.event[Payload](name)` declares a descriptor; it does not install a listener or retain previous notifications.

## Destinations

| API | Destination and lifetime |
| --- | --- |
| `CommandContext.emit_to_caller(event, payload)` | The page that issued the current command |
| `WindowContext.events()` | Produces a window event emitter |
| `WindowEventEmitter.emit(event, payload)` | The associated window while it remains alive |

Host payloads require `ToJson`. Window emitters belong to window lifetime; a saved emitter must be removed from application state when that window closes. Emission is not an implicit broadcast to all windows.

## Subscriptions

`proton_client.subscribe(event, listener, failure)` decodes payloads through `FromJson` and returns a `Subscription`. `Subscription.close()` releases the listener. Subscription setup can raise `ClientFailure`; event decoding failures are reported as `EventDecode` through the failure callback.

`proton_rabbita.subscribe` integrates subscription ownership into Rabbita. Its options include a subscription key, retry count, ready command and client override; full signatures are in the [Rabbita API](https://mooncakes.io/docs/moonbit-community/proton_rabbita@0.3.0/).

The JavaScript interface is `window.__MoonBit__.app.on(name, callback)`. The callback receives an event envelope containing `payload`; registration returns an unsubscribe function.

## Delivery semantics

- Notifications missed before subscription are not replayed.
- Command responses and events are separate deliveries; their relative order is not an application synchronization contract.
- Listener disposal ends observation; events are not a durable queue or acknowledgment protocol.
- A notification that state changed can invalidate a frontend query. The authoritative snapshot is obtained through a command.

The [event tutorial](tutorial/events.md) demonstrates subscription and cleanup. The [Todo tutorial](tutorial/isomorphic.md) demonstrates invalidation followed by a snapshot query.
