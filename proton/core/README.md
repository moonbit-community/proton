# proton/core

`moonbit-community/proton/core` owns the bridge between native MoonBit code and page
JavaScript.

It provides:

- op registration and dispatch
- command host dispatch over the IPC protocol
- `window.__MoonBit__` bridge wiring
- extension events

Application lifecycle and app composition belong in the root `proton` facade,
which owns the source-built native runtime and its async host loop.

`AppCommandHost` owns command registration, registration sealing, dispatch, and
closure. `MbtProcessHost` is an alias of the same type; its constructor and
`dispatch_async` / `dispatch_async_with_context` names remain available as aliases.
Synchronous, asynchronous, and context-aware handlers share one command namespace.
Sealing stops registration without disabling existing commands; closing rejects
future dispatches.
