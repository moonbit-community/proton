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
- `justjavac/lepus_cli`: developer CLI entry point, including build-time command/event code generation in `cli/codegen`
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
- make package-level `@lepus.html(...)` and `@lepus.config(...)`
  the ordinary app startup path while keeping `create_app(...)` and
  `create_app_from_file(...)` as lower-level escape hatches

JavaScript now uses a single global entry:

- `window.__MoonBit__`

## Project Model

Lepus separates app configuration from capability declaration:

- `app.json` declares app shape such as window, entry, and debug settings
- application code explicitly declares the extensions that should ship
- the runtime only installs the extensions that were declared in MoonBit code

This separation is important for binary size. Metadata and manifests may help AI discover extensions, but they should not imply that every built-in extension gets linked automatically.

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
  @lepus.html("Demo", "<html></html>", width=900, height=700, debug=true)
  .extension(@fs.extension())
  .extension(@path.extension())
  .run_or_abort()
}
```

Or from `app.json`:

```moonbit
async fn main {
  @lepus.config("app.json")
  .extension(@fs.extension())
  .extension(@path.extension())
  .run_or_abort()
}
```

`app.json` configures the app window, entry, and debug mode. Extensions are declared in MoonBit code:

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
  "debug": 1
}
```

The important rule is:

- `app.json` configures the app
- MoonBit code declares and enables extensions
- `App::extension(...)` links and enables one extension in one call
- `App::extensions(...)` links and enables an explicit extension set such as
  `@lepus_ext.all()`

Even when catalog or tooling generates those edits, the final project should still make extension linking explicit and reviewable.

### Install The Codegen CLI

Generated command extensions call `target/lepus-tools/lepus codegen` from
package pre-build steps. Install the local CLI before building those packages:

```powershell
moon install --path cli --bin target\lepus-tools
Copy-Item target\lepus-tools\lepus_cli.exe target\lepus-tools\lepus.exe -Force
```

On Unix-like shells, copy `target/lepus-tools/lepus_cli` to
`target/lepus-tools/lepus` and make it executable.

### Run The Windows CEF Example

Run from the repository root in one PowerShell session:

```powershell
node .\scripts\setup_cef.mjs
moon build src\cef_process --target native
moon -C examples run 37_cef_mvp --target native
```

The setup script installs CEF directly into `.cef-cache/` and writes
`.cef-cache/version.txt`. If CEF is missing, Windows native builds fail with
the same install command.

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
  installed in `.cef-cache/` by `node .\scripts\setup_cef.mjs`.
- `.cef-cache/` must contain a CEF binary distribution directly, with
  `include/capi/cef_app_capi.h`, `Release/libcef.lib`,
  `Release/libcef.dll`, `Resources/icudtl.dat`, and `version.txt` at the root.
  The setup script also mirrors early-startup resource files such as
  `icudtl.dat` and `*.pak` into `Release/`, because CEF loads them from the
  `libcef.dll` directory before normal settings are fully applied.
- CEF child processes run through the MoonBit helper package
  `src/cef_process`, not through the user executable. Build it first with
  `moon build src\cef_process --target native`. A deployed app should package
  `cef_process.exe` beside the app executable.
- The native stub loads `Release/libcef.dll` and points CEF at `Resources/`
  from the configured root. A deployed app can package the same CEF runtime
  layout beside the app executable.
- Set `LEPUS_CEF_REMOTE_DEBUGGING_PORT` to a port number to enable CEF remote
  debugging for CDP-based smoke tests.
- On Windows, missing CEF fails the native build with setup instructions.
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
