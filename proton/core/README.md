# proton/core

`justjavac/proton/core` owns the bridge between native MoonBit code and page
JavaScript.

It provides:

- extension specs and installation
- op registration and dispatch
- resource tables
- `window.__MoonBit__` bridge wiring
- extension events

Application lifecycle and app composition belong in the root `proton` facade,
which drives the native Proton dynamic library.
