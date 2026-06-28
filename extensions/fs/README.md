# FS Extension

`justjavac/proton_ext/fs` contains filesystem extension definitions and helper
logic for future bridge integration.

It is not currently wired into the active native DLL runtime route. The current
supported application path is the root facade under `justjavac/proton`;
filesystem calls are not exposed to pages until the native bridge/event layer is
implemented.

## Scope

- File and directory operation definitions.
- Resource-id streaming model.
- Activity event metadata.
- Metadata used by catalog and code generation checks.

## Safety Notes

- This extension grants direct host filesystem access when eventually exposed.
- Use it only with trusted local HTML/JavaScript.
- Text helpers use UTF-8 payloads.
