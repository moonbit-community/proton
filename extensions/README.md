# Extensions

This workspace contains the built-in extension packages that plug into
`justjavac/lepus_core` and `justjavac/lepus_app`.

They now participate in app startup through `justjavac/lepus_app`, and each
package exposes a `spec()` builder for registry-driven installation.

## Layout

- `fs/`: filesystem helpers and rid-based file streaming
- `path/`: path transforms such as `resolve`, `join`, and `dirname`
- `dialog/`: native message and file dialogs
- `clipboard/`: adapter over the published `justjavac/clipboard` package
- `auto_launch/`: startup-entry management through `justjavac/auto_launch`
- `devtools/`: open the native developer tools window from trusted JavaScript
- `shell/`: open external targets and reveal files
- `keepawake/`: native keep-awake guards through `justjavac/keepawake`
- `microphone/`: native microphone discovery and capture-config helpers
- `notification/`: native notification helpers
- `tray/`: native tray icon helpers
- `global_hotkey/`: native global hotkey helpers

For host-agnostic desktop features, prefer the sibling standalone modules
[`notification/`](../notification), [`tray/`](../tray), and
[`global_hotkey/`](../global_hotkey), plus the published Mooncakes packages
[`justjavac/clipboard`](https://mooncakes.io/docs/justjavac/clipboard),
[`justjavac/auto_launch`](https://mooncakes.io/docs/justjavac/auto_launch),
[`justjavac/keepawake`](https://mooncakes.io/docs/justjavac/keepawake), and
[`justjavac/microphone`](https://mooncakes.io/docs/justjavac/microphone). The
extensions in this workspace adapt those capabilities into the webview runtime.

## Usage

Add the workspace as a local dependency:

```json
{
  "deps": {
    "extensions": {
      "path": "../extensions"
    }
  }
}
```

### Direct installation on a raw webview

```moonbit
import {
  "justjavac/lepus_core" @core,
  "extensions/path" @path,
  "justjavac/lepus" @webview,
}

fn main {
  let webview = @webview.Webview::new()
  @core.install_extension(webview, @path.extension())
  webview.run()
}
```

### App-style installation

```moonbit
import {
  "extensions/fs" @fs,
  "extensions/path" @path,
  "justjavac/lepus_app" @app,
  "justjavac/lepus_manifest" @manifest,
  "justjavac/lepus_runtime" @wvrt,
}

fn main {
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("Demo", 900, 700),
    @manifest.AppEntry::Html("<html></html>"),
    debug=1,
  )
  let registry = @app.ExtensionRegistry::new()
  let _ = registry.register(@fs.spec())
  let _ = registry.register(@path.spec())
  let runtime : @wvrt.App = match @app.create_app(manifest, registry) {
    Ok(app) => app
    Err(error) => abort(error)
  }
  runtime.run()
}
```

In this model:

- MoonBit code registers which extensions are available.
- `justjavac/lepus_tooling` can generate the same explicit registry-module edits from metadata when you do not want to hand-maintain the registry.
- `app.json.extensions` enables or disables registered extensions and can pass options.
- JavaScript talks to one global object: `window.__MoonBit__`.
- Each extension owns `extension.json` and `options.schema.json` for machine-readable metadata.

Example config:

```json
{
  "window": { "title": "Demo", "width": 900, "height": 700 },
  "entry": { "kind": "file", "value": "app.html" },
  "extensions": {
    "justjavac/lepus-fs": true,
    "justjavac/lepus-path": {}
  },
  "debug": 1
}
```

## JavaScript Surface

Built-in and custom extensions share the same shape:

```js
await window.__MoonBit__.fs.readFile("demo.txt");
await window.__MoonBit__.path.resolve({ path: "." });
window.__MoonBit__.events.on("fs.activity", console.log);
```

## Notes

- These extensions currently target `native`.
- `fs.open(...)` and `fs.openFile(...)` return a resource id in the `rid` field.
- `path` is pure and side-effect free.
- `autoLaunch` manages host startup entries and should be linked only for apps
  that explicitly expose that desktop integration.
- `devtools` exposes the native developer tools window and should stay opt-in
  for trusted development builds.
- `keepAwake` owns one active native guard per installed extension instance.
- `microphone` currently exposes device discovery and capture configuration
  helpers; capture-session streaming can be layered on once the package exposes
  that as public API.
- `devtools`, `dialog`, `shell`, `notification`, `tray`, and `globalHotkey`
  currently ship Windows-native implementations in this repository.
- `clipboard` follows the upstream
  [`justjavac/clipboard`](https://mooncakes.io/docs/justjavac/clipboard)
  platform matrix.


