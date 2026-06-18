# lepus_app

High-level app composition helpers for `lepus`.

`lepus_app` turns inline app configuration or an `app.json` file plus explicit
extension links into a runtime `App`.

- `html(...)`, `url(...)`, `file(...)`, `asset(...)`, and `from_file(...)`
  are the preferred app startup facade. Use `.extension(...)` for
  framework-side extensions, `.command(...)` for user-process command
  extensions, and `.run_or_abort()` for the common entrypoint.
- `create_app(...)` builds from an `AppManifest` when callers need a lower-level
  escape hatch
- `create_app_from_file(...)` builds from the bootstrap control plane and keeps
  manifest file loading aligned with the same `app.json` editing backend used
  by tooling
- `run_app_command_extensions_with_framework_process(...)` is async; it runs
  user command extensions in the current process and starts a framework/webview
  child process
- `run_app_command_host_with_framework_process(...)` is the lower-level async
  API for user processes that register an `AppCommandHost`, start a local IPC
  server, and launch a framework/webview child process
- `run_framework_process_from_cli(...)` is the framework-child entrypoint used
  by reusable or single-binary framework processes

The package no longer treats `AppPlan` as a public concept. Planning remains an
internal implementation detail so the user-facing API stays focused on app
creation.

Inline apps can keep framework process, manifest, registry, and IPC details out
of user code:

```moonbit
async fn main {
  @app.html("Demo", 900, 700, resource, debug=1)
    .extension(@fs.spec())
    .command(generated_app_command_extension())
    .run_or_abort()
}
```
