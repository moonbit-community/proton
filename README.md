# Proton

Proton is a MoonBit framework for native desktop apps backed by CEF.
Applications compose a small runtime with explicitly linked extensions.

## Packages

- `justjavac/proton`: app facade, including `@proton.html(...)` and `@proton.config(...)`
- `justjavac/proton/webview`: low-level native WebView binding
- `justjavac/proton/core`: JavaScript bridge, ops dispatch, and extension host
- `justjavac/proton/runtime`: app and window lifecycle
- `justjavac/proton/manifest`: runtime manifest types
- `justjavac/proton/bootstrap`: `moon.proton` loading and project config decoding
- `justjavac/proton/catalog`: `moon.ext` discovery and link-plan helpers
- `justjavac/proton_config`: parser for `moon.proton`, `moon.ext`, and `moon.mod`
- `justjavac/proton_cli`: developer CLI and command/event codegen
- `justjavac/proton_ext`: built-in extensions such as `fs`, `path`, `dialog`, and `shell`

## App Startup

```moonbit
import {
  "justjavac/proton"
  "justjavac/proton_ext/fs" @fs
  "justjavac/proton_ext/path" @path
}

async fn main {
  @proton.html("Demo", "<html></html>", width=900, height=700, debug=true)
  .extension(@fs.extension())
  .extension(@path.extension())
  .run_or_abort()
}
```

Config-file startup uses `moon.proton`. Extensions are still declared in
MoonBit code.

```moonbit
async fn main {
  @proton.config("moon.proton")
  .extension(@fs.extension())
  .extension(@path.extension())
  .run_or_abort()
}
```

```moonbit
window = {
  title: "Demo",
  width: 960,
  height: 720,
}

entry = {
  kind: "file",
  value: "app.html",
}

debug = true
```

## JavaScript Surface

Proton installs one global object:

```js
await window.__MoonBit__.fs.readFile("demo.txt");
await window.__MoonBit__.path.resolve({ path: "." });
window.__MoonBit__.events.on("fs.activity", console.log);
```

Low-level custom calls can use:

```js
await window.__MoonBit__.core.invokeOp("ext:path/resolve", { path: "." });
```

## Common Commands

Install CEF for Windows native builds:

```powershell
node .\scripts\setup_cef.mjs
```

Build examples:

```powershell
moon -C examples build --target native
```

Install the local codegen CLI used by generated-command examples:

```powershell
moon install --path cli --bin target\proton-tools
Copy-Item target\proton-tools\proton_cli.exe target\proton-tools\proton.exe -Force
```

Run CEF smoke checks:

```powershell
moon build src\cef_process --target native
moon -C examples run 43_cef_bind_smoke --target native
node .\scripts\e2e_cdp_smoke.mjs
```

## Notes

- This repository currently targets `native`.
- The CEF runtime lives in `.cef-cache/` and is installed by `scripts/setup_cef.mjs`.
- CEF child processes use `src/cef_process`; packaged apps should ship the helper beside the app executable.
- Extension linking is explicit so applications only ship the capabilities they enable.

## License

MIT. See [LICENSE.md](LICENSE.md).
