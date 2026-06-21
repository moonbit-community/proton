# FS Extension

`justjavac/proton_ext/fs` exposes host filesystem helpers under
`window.__MoonBit__.fs`.

Install it explicitly:

```moonbit
import {
  "justjavac/proton"
  "justjavac/proton_ext/fs" @fs
}

async fn main {
  @proton.html("FS Demo", "<html></html>", width=900, height=700, debug=true)
  .extension(@fs.extension())
  .run_or_abort()
}
```

## JavaScript API

Common file helpers:

```js
await window.__MoonBit__.fs.writeFile("demo.txt", "Hello");
const text = await window.__MoonBit__.fs.readFile("demo.txt");
const stat = await window.__MoonBit__.fs.stat("demo.txt", {
  throwIfNoEntry: false,
});
```

Directory and path operations include `readdir`, `mkdir`, `unlink`, `rm`,
`rename`, `copyFile`, `realpath`, `truncate`, `size`, and `exists`.

Streaming uses resource ids:

```js
const { rid } = await window.__MoonBit__.fs.openFile("demo.txt", {
  write: true,
});
await window.__MoonBit__.fs.write(rid, "chunk");
await window.__MoonBit__.fs.flush(rid);
await window.__MoonBit__.fs.close(rid);
```

The extension emits `fs.activity` after successful operations:

```js
window.__MoonBit__.events.on("fs.activity", console.log);
```

## Notes

- This extension grants direct host filesystem access.
- Use it only with trusted local HTML/JavaScript.
- Text helpers use UTF-8 payloads.
- `openFile` covers common read/write/append modes; lower-level edge cases can
  be added as needed.
