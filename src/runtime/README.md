# proton/runtime

`justjavac/proton/runtime` owns app and window lifecycle on top of
`justjavac/proton/core`.

Use this package when you need lower-level `App` or `AppWindow` control. For
ordinary applications, prefer the root `justjavac/proton` facade.

## Responsibilities

- create and run app windows
- apply runtime manifests
- install explicitly provided extension specs
- keep `AppEntry::Asset` as a tooling distinction while loading it as a local file

## Related Packages

- `justjavac/proton/core`: bridge, ops runtime, and extension host
- `justjavac/proton/bootstrap`: `moon.proton` loading
- `justjavac/proton`: ergonomic app composition
