# proton/core

`moonbit-community/proton/core` owns the bridge between native MoonBit code and page
JavaScript.

It provides:

- op registration and dispatch
- command host dispatch over the IPC protocol
- `window.__MoonBit__` bridge wiring
- extension events

Application lifecycle and app composition belong in the root `proton` facade,
which drives the native Proton dynamic library.
