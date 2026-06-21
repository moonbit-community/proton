# Extensions

`justjavac/proton_ext` contains built-in extensions for Proton apps.

Each extension exposes `extension()` for app-style startup and owns a `moon.ext`
metadata file for tooling.

## Packages

- `fs`: host filesystem helpers and resource-id streaming
- `path`: path transforms such as `resolve`, `join`, and `dirname`
- `dialog`: native dialogs
- `clipboard`: clipboard adapter
- `shell`: open or reveal host paths
- `notification`: native notifications
- `tray`: tray icon helpers
- `global_hotkey`: global hotkey helpers
- `auto_launch`: startup-entry management
- `keepawake`: native keep-awake guards
- `microphone`: microphone discovery and capture config helpers

## Usage

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

JavaScript calls extensions through `window.__MoonBit__`:

```js
await window.__MoonBit__.fs.readFile("demo.txt");
await window.__MoonBit__.path.resolve({ path: "." });
window.__MoonBit__.events.on("fs.activity", console.log);
```

Extensions are opt-in. `moon.proton` configures the app; MoonBit code chooses
the capabilities that ship.
