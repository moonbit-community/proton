# Proton

Proton is a MoonBit framework for native desktop apps backed by CEF. It gives
MoonBit apps a browser window, a JavaScript bridge, and opt-in native
extensions such as filesystem, path, dialog, clipboard, notification, tray, and
global hotkeys.

## Install The CLI

Install the released CLI from the MoonBit registry:

```sh
moon install justjavac/proton_cli
```

This installs the `proton_cli` command into MoonBit's binary directory
(`~/.moon/bin` by default). Make sure that directory is on `PATH`.

Use the CLI to install the local CEF runtime for the current project:

```sh
proton_cli cef setup
```

## Add Proton To An App

Add the runtime and whichever extension package you need:

```sh
moon add justjavac/proton@0.1.2
moon add justjavac/proton_ext@0.1.3
```

Your executable package should target native and import the packages it uses:

```moon.pkg
import {
  "moonbitlang/async",
  "justjavac/proton",
  "justjavac/proton_ext/fs",
  "justjavac/proton_ext/path",
}

supported_targets = "native"

options(
  "is-main": true,
)
```

Start an app directly from HTML:

```moonbit
import {
  "justjavac/proton"
  "justjavac/proton_ext/fs" @fs
  "justjavac/proton_ext/path" @path
}

async fn main {
  let app =
    @proton.html("Demo", "<html></html>", width=900, height=700, debug=true)
    .extension(@fs.extension())
    .extension(@path.extension())
  app.run_or_abort()
}
```

Or keep window and entry settings in `moon.proton`:

```moonbit
async fn main {
  let app =
    @proton.config("moon.proton")
    .extension(@fs.extension())
    .extension(@path.extension())
  app.run_or_abort()
}
```

`moon.proton` configures app settings such as window size, entry HTML, debug
mode, frontend build metadata, and bundle metadata. Extensions are still linked
explicitly in MoonBit code so apps only ship the capabilities they use.

## JavaScript Bridge

Proton exposes one global object to the web page:

```js
await window.__MoonBit__.fs.readFile("demo.txt");
await window.__MoonBit__.path.resolve({ path: "." });
window.__MoonBit__.events.on("fs.activity", console.log);
```

Low-level custom calls can use the core op bridge:

```js
await window.__MoonBit__.core.invokeOp("ext:path/resolve", { path: "." });
```

## Run This Repository's Examples

The examples include generated command extensions. Install the released CLI
into the repository tool directory before building them:

```sh
moon install justjavac/proton_cli --bin target/proton-tools
```

No local `--path` install or binary copy is needed. The examples call
`target/proton-tools/proton_cli` directly.

Set up CEF, build the helper process, then build or run examples:

```sh
target/proton-tools/proton_cli cef setup
moon -C proton build cef_process --target native
moon -C examples build --target native
moon -C examples run 43_cef_bind_smoke --target native
```

Run the CDP-based smoke scenarios:

```sh
node ./scripts/e2e_cdp_smoke.mjs
```

## Packages

- `justjavac/proton`: app facade with `@proton.html(...)` and `@proton.config(...)`
- `justjavac/proton/webview`: low-level native WebView binding
- `justjavac/proton/core`: JavaScript bridge, ops dispatch, and extension host
- `justjavac/proton/runtime`: app and window lifecycle
- `justjavac/proton_config`: parser for `moon.proton`, `moon.ext`, and `moon.mod`
- `justjavac/proton_cli`: CEF setup and command/event code generation
- `justjavac/proton_ext`: built-in opt-in extensions

## Notes

- Proton currently targets MoonBit `native`.
- The CEF runtime lives in `.cef-cache/` after `proton_cli cef setup`.
- CEF child processes use `proton/cef_process`; packaged apps should ship the
  helper beside the app executable.
- Command extensions are generated with `proton_cli codegen`.

## License

MIT. See [LICENSE.md](LICENSE.md).
