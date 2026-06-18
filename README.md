# Lepus

MoonBit framework for building Tauri/Electron-style desktop apps on top of a small native browser backend, with a compact runtime, manifest-driven control plane, and opt-in JS-facing extensions so applications only link the native capabilities they actually use.

The repository is organized into these layers:

- `justjavac/lepus`: high-level app facade and ordinary developer API
- `justjavac/lepus/webview`: low-level native browser binding
- `justjavac/lepus/manifest`: declarative `app.json` contract types
- `justjavac/lepus/core`: native/JS bridge, ops runtime, resource tables, extension host
- `justjavac/lepus/runtime`: `App`, windows, and lifecycle orchestration
- `justjavac/lepus/bootstrap`: `app.json` loading, editing, and validation helpers
- `justjavac/lepus/catalog`: metadata discovery, schema loading, and explicit link planning
- `justjavac/lepus/cli`: developer CLI entry point, including build-time command/event code generation in `src/cli/codegen`
- `justjavac/lepus_ext/*`: built-in extensions such as `fs`, `path`, `dialog`, `clipboard`, `shell`, `notification`, `tray`, and `globalHotkey`

The product direction is:

- keep the runtime small
- keep extension linking explicit
- keep AI support in metadata, manifests, diagnostics, and tooling rather than in every shipped runtime

In one sentence: Lepus is aiming for "small runtime, rich control plane".

## Direction

The near-term direction is:

- keep Lepus framework-first rather than app-template-first
- keep extensions opt-in so shipped binaries stay small
- add AI support in metadata, tooling, diagnostics, and manifest control-plane layers rather than the default runtime of every app
- make package-level `@lepus.html(...)` and `@lepus.from_config_file(...)`
  the ordinary app startup path while keeping `create_app(...)` and
  `create_app_from_file(...)` as lower-level escape hatches

JavaScript now uses a single global entry:

- `window.__MoonBit__`

## Project Model

Lepus separates declaration, linking, and runtime state:

- `app.json` declares app shape and extension configuration
- application code or generated project files explicitly link the extensions that should ship
- the runtime only installs the extensions that were actually linked and selected

This separation is important for binary size. Metadata and manifests may help AI discover and configure extensions, but they should not imply that every built-in extension gets linked automatically.

## Quick Start

Low-level usage stays very small:

```moonbit
import {
  "justjavac/lepus/webview" @webview
}

fn main {
  @webview.Webview::new(debug=1)
  ..set_title("Lepus")
  ..set_size(800, 600, @webview.SizeHint::None)
  ..set_html("<html><body><h1>Hello</h1></body></html>")
  .run()
}
```

App-style startup goes through `justjavac/lepus`:

```moonbit
import {
  "justjavac/lepus"
  "justjavac/lepus_ext/fs" @fs
  "justjavac/lepus_ext/path" @path
}

async fn main {
  @lepus.html("Demo", 900, 700, "<html></html>", debug=1)
  .extension(@fs.spec())
  .extension(@path.spec())
  .run_or_abort()
}
```

Or from `app.json`:

```moonbit
async fn main {
  @lepus.from_config_file("app.json")
  .link(@fs.spec())
  .link(@path.spec())
  .run_or_abort()
}
```

`app.json` declares which linked extensions are enabled and can pass per-extension options:

```json
{
  "window": {
    "title": "Demo",
    "width": 960,
    "height": 720
  },
  "entry": {
    "kind": "file",
    "value": "app.html"
  },
  "extensions": {
    "justjavac/lepus-fs": true,
    "justjavac/lepus-path": {}
  },
  "debug": 1
}
```

The important rule is:

- `app.json` configures extensions
- explicit project code or generated registry code links extensions
- inline `App::extension(...)` links and enables an extension in one call
- config-file `App::link(...)` only links; `app.json.extensions` remains the
  source of enablement

Even when catalog or tooling generates those edits, the final project should still make extension linking explicit and reviewable.

### Install The Codegen CLI

Generated command extensions call `target/lepus-tools/lepus codegen` from
package pre-build steps. Install the local CLI before building those packages:

```powershell
moon install --path src\cli --bin target\lepus-tools
Copy-Item target\lepus-tools\cli.exe target\lepus-tools\lepus.exe -Force
```

On Unix-like shells, copy `target/lepus-tools/cli` to
`target/lepus-tools/lepus` and make it executable.

### Run The Windows CEF Example

Run from the repository root in one PowerShell session:

```powershell
node .\scripts\setup_cef.mjs
$env:LEPUS_CEF_ROOT = (Resolve-Path ".\.cef-cache\cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_windows64_minimal").Path
Remove-Item Env:\LEPUS_CEF_SUBPROCESS_PATH -ErrorAction SilentlyContinue
moon build src\cef_process --target native
$env:LEPUS_CEF_SUBPROCESS_PATH = (Resolve-Path "_build\native\debug\build\justjavac\lepus\cef_process\cef_process.exe").Path
moon -C examples run 37_cef_mvp --target native
```

If CEF is already downloaded elsewhere, set `LEPUS_CEF_ROOT` to that directory
instead of running the download script:

```powershell
$env:LEPUS_CEF_ROOT = "<path-to-extracted-cef-root>"
```

Run the automated CEF bind smoke test with the same environment:

```powershell
moon -C examples run 43_cef_bind_smoke --target native
```

The smoke test prints `["ok"]` when the CEF backend, subprocess helper, and
JavaScript binding bridge are working. The MSVC `LNK4044` warning about `/link`
is expected with the current MoonBit linker flag forwarding.

## JavaScript Surface

The runtime installs one global object:

- `window.__MoonBit__.events.on(...)`
- `window.__MoonBit__.<extension>.*`
- `window.__MoonBit__.core.invokeOp(name, payload)` for low-level debugging and custom experiments

Example:

```js
await window.__MoonBit__.fs.readFile("demo.txt");
await window.__MoonBit__.path.resolve({ path: "." });
await window.__MoonBit__.core.invokeOp("ext:path/resolve", { path: "." });
window.__MoonBit__.events.on("fs.activity", console.log);
```

## Native Notes

This repo targets `native` only.

- The low-level `justjavac/lepus/webview` package uses a Windows CEF backend
  supplied by `LEPUS_CEF_ROOT`.
- `LEPUS_CEF_ROOT` must point at a CEF binary distribution with
  `include/capi/cef_app_capi.h`, `Release/libcef.lib`,
  `Release/libcef.dll`, and `Resources/icudtl.dat`.
- CEF child processes run through the MoonBit helper package
  `src/cef_process`, not through the user executable. Build it first and pass
  its executable path through `LEPUS_CEF_SUBPROCESS_PATH` when building or
  running CEF examples.
- With `LEPUS_CEF_ROOT` and `LEPUS_CEF_SUBPROCESS_PATH` set, the native stub
  loads `Release/libcef.dll` and points CEF at `Resources/` from the configured
  root. A deployed app can either keep those environment variables or package
  the same CEF runtime layout beside the app.
- Set `LEPUS_CEF_REMOTE_DEBUGGING_PORT` to a port number to enable CEF remote
  debugging for CDP-based smoke tests.
- If `LEPUS_CEF_ROOT` is unset, native checks can still compile against an
  unavailable stub, but creating a real `Webview` aborts with a CEF setup
  message.
- The previous vendored webview linkage path has been removed from the root
  package.
- The first production target for the CEF backend is Windows. macOS and Linux
  CEF parity is deferred.
- `clipboard` comes from the published Mooncakes package `justjavac/clipboard`.
- `notification` comes from the published Mooncakes package `justjavac/notification`.
- `tray` is provided by the published Mooncakes package `justjavac/tray`.
- `globalHotkey` comes from the published Mooncakes package `justjavac/global_hotkey`.
- WIP: `dialog` and `shell` are currently Windows-native in this repository.

## License

MIT. See [LICENSE.md](LICENSE.md).
