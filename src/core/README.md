# proton/core

`justjavac/proton/core` owns the bridge between native MoonBit code and page
JavaScript.

It provides:

- extension specs and installation
- op registration and dispatch
- resource tables
- `window.__MoonBit__` bridge setup
- extension events

Application lifecycle belongs in `runtime`; app composition belongs in the root
`proton` facade.
