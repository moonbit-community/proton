# lepus_app

High-level app composition helpers for `lepus`.

`lepus_app` turns a parsed manifest plus an explicit `ExtensionRegistry` into a
runtime `App`.

- `create_app(...)` builds from an `AppManifest`
- `create_app_from_file(...)` builds from the bootstrap control plane and keeps
  manifest file loading aligned with the same `app.json` editing backend used
  by tooling
- `create_app_with_service(...)` and
  `create_app_from_file_with_service(...)` build the same runtime while
  installing an explicit app service for application ops

The package no longer treats `AppPlan` as a public concept. Planning remains an
internal implementation detail so the user-facing API stays focused on app
creation.
