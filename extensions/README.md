# Extensions

This workspace contains the built-in extension packages that plug into
`justjavac/lepus/core` and `justjavac/lepus`.

They participate in app startup through `justjavac/lepus`, and each package
exposes `extension()` as its ordinary app-facing entrypoint.

## Layout

- `fs/`: filesystem helpers and rid-based file streaming
- `path/`: path transforms such as `resolve`, `join`, and `dirname`
- `dialog/`: native message and file dialogs
- `clipboard/`: adapter over the published `justjavac/clipboard` package
- `auto_launch/`: startup-entry management through `justjavac/auto_launch`
- `shell/`: open external targets and reveal files
- `keepawake/`: native keep-awake guards through `justjavac/keepawake`
- `microphone/`: native microphone discovery and capture-config helpers
- `notification/`: native notification helpers
- `tray/`: native tray icon helpers
- `global_hotkey/`: native global hotkey helpers

For host-agnostic desktop features, prefer the published Mooncakes packages
[`justjavac/clipboard`](https://mooncakes.io/docs/justjavac/clipboard),
[`justjavac/notification`](https://mooncakes.io/docs/justjavac/notification),
[`justjavac/tray`](https://mooncakes.io/docs/justjavac/tray),
[`justjavac/global_hotkey`](https://mooncakes.io/docs/justjavac/global_hotkey),
[`justjavac/auto_launch`](https://mooncakes.io/docs/justjavac/auto_launch),
[`justjavac/keepawake`](https://mooncakes.io/docs/justjavac/keepawake), and
[`justjavac/microphone`](https://mooncakes.io/docs/justjavac/microphone). The
extensions in this workspace adapt those capabilities into the webview runtime.

## Usage

Add the extension module as a dependency:

```toml
import {
  "justjavac/lepus_ext@0.1.0"
}
```

### Direct installation on a raw webview

```moonbit
import {
  "justjavac/lepus/core" @core
  "justjavac/lepus/webview" @webview
  "justjavac/lepus_ext/path" @path
}

fn main {
  let webview = @webview.Webview::new()
  @core.install_extension(webview, @path.core_extension())
  webview.run()
}
```

### App-style installation

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

In this model:

- MoonBit code declares and enables extensions.
- `app.json` configures app-level settings such as window, entry, and debug mode.
- JavaScript talks to one global object: `window.__MoonBit__`.
- Each extension owns `extension.json` and `options.schema.json` for machine-readable metadata.

Example config:

```json
{
  "window": { "title": "Demo", "width": 900, "height": 700 },
  "entry": { "kind": "file", "value": "app.html" },
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
- `keepAwake` owns one active native guard per installed extension instance.
- `microphone` currently exposes device discovery and capture configuration
  helpers; capture-session streaming can be layered on once the package exposes
  that as public API.
- `dialog` and `shell` currently ship Windows-native implementations in this
  repository.
- `globalHotkey` follows the upstream
  [`justjavac/global_hotkey`](https://mooncakes.io/docs/justjavac/global_hotkey)
  platform matrix.
- `notification` follows the upstream
  [`justjavac/notification`](https://mooncakes.io/docs/justjavac/notification)
  platform matrix.
- `tray` follows the upstream
  [`justjavac/tray`](https://mooncakes.io/docs/justjavac/tray)
  platform matrix.
- `clipboard` follows the upstream
  [`justjavac/clipboard`](https://mooncakes.io/docs/justjavac/clipboard)
  platform matrix.


