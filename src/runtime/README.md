# lepus/runtime

`justjavac/lepus/runtime` is the lifecycle layer for app and window orchestration.
It sits on top of `justjavac/lepus/core`, which owns the native/JS bridge,
ops runtime, resource tables, and low-level extension installation.

Use:

- `justjavac/lepus/webview` for the raw native `Webview`
- `justjavac/lepus/core` for `Extension`, `ExtensionSpec`, low-level install,
  and the `window.__MoonBit__` bridge
- `justjavac/lepus/runtime` for `App`, `AppWindow`, and multi-window lifecycle
- `justjavac/lepus/bootstrap` for manifest loading/editing
- `justjavac/lepus` for registry-driven app planning and creation

This package does not decide which extensions are installed. That composition
step now lives in `justjavac/lepus`, while built-in extension packages live in
the separate `justjavac/lepus_ext` module.

## JavaScript Surface

The runtime installs a single global object:

- `window.__MoonBit__.events.on(...)`
- `window.__MoonBit__.<extension>.*`
- `window.__MoonBit__.core.invokeOp(name, payload)` for low-level debugging

Built-in and custom extensions use the same shape. For example:

```js
await window.__MoonBit__.fs.readFile("demo.txt");
await window.__MoonBit__.echo.ping({ text: "hello" });
window.__MoonBit__.events.on("fs.activity", console.log);
```

`AppEntry::Asset` is treated as a local file entry by the runtime. It is kept as
a manifest-level distinction for tooling, but the runtime no longer installs a
backend-specific synthetic origin.

## Typical Usage

For direct installation on a raw webview:

```moonbit
import {
  "justjavac/lepus/core" @core
  "justjavac/lepus/webview" @webview
  "justjavac/lepus_ext/path" @path
}

fn main {
  let webview = @webview.Webview::new(debug=1)
  @core.install_extension(webview, @path.extension())
  webview.run()
}
```

For normal app-style startup, prefer `justjavac/lepus`:

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
