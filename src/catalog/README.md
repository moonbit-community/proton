# proton/catalog

Metadata discovery and link-planning helpers for Proton extensions.

`justjavac/proton/catalog` is intentionally metadata-only.

- it scans explicit search roots for `moon.ext`
- it loads descriptors without importing extension code
- it builds deterministic link plans from metadata dependencies

Built-in and third-party extensions use the same catalog path: if they expose
`moon.ext`, they can be discovered the same way.
