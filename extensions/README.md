# Extensions

`justjavac/proton_ext` contains Proton extension packages for the native DLL
route. Generated app-command extensions expose host capabilities through the
Proton bridge and keep metadata for catalog/codegen validation.

The current supported route is:

```text
MoonBit app -> justjavac/proton -> proton dynamic library -> command bridge
```

Applications register extensions with `.extension(...)`. Inline HTML entries
can call generated proxies such as `window.__MoonBit__.fs.readText(...)` or the
low-level `window.__MoonBit__.core.invokeOp(...)` bridge, depending on the
extension and example.

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

Extension metadata is used by code generation, catalog checks, dependency
planning, and generated command bridge packages. Applications should register
extensions in top-level Proton code with `.extension(...)`; `moon.proton`
extension settings are not the active configuration surface.
