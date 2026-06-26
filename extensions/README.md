# Extensions

`justjavac/proton_ext` currently contains metadata and implementation pieces for
future Proton extension tooling.

These packages are not part of the active native DLL runtime route yet. The
current supported route is:

```text
MoonBit app -> justjavac/proton -> proton dynamic library
```

Do not treat these packages as a runnable app API until the native DLL route has
an implemented bridge/event layer that exposes extension calls.

## Packages

- `fs`: host filesystem helper definitions
- `path`: path transform helper definitions
- `dialog`: native dialog helper definitions
- `clipboard`: clipboard helper definitions
- `shell`: open/reveal host path helper definitions
- `notification`: native notification helper definitions
- `tray`: tray icon helper definitions
- `global_hotkey`: global hotkey helper definitions
- `auto_launch`: startup-entry helper definitions
- `keepawake`: keep-awake helper definitions
- `microphone`: microphone discovery/capture helper definitions

## Current Rule

Extension metadata may be useful to code generation, catalog checks, and future
bridge work. Applications may keep `.extension(...)` calls in top-level Proton
code, but pages cannot call those extensions until the native bridge/event layer
exists.
