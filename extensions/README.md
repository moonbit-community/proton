# Extensions

`justjavac/proton_ext` contains command extensions that plug into the active
native DLL runtime route:

```text
MoonBit app -> justjavac/proton -> proton dynamic library -> extension bridge
```

Apps register extensions with `.extension(...)`. Inline HTML pages call the
generated JavaScript proxies through `window.__MoonBit__.<namespace>` and
subscribe to events through either `window.__MoonBit__.events.on(...)` or
`window.__MoonBit__.<namespace>.on(...)`.

## Packages

- `fs`: host filesystem helper definitions
- `path`: path transform helper definitions
- `dialog`: native dialog helper definitions
- `clipboard`: clipboard helper definitions
- `shell`: open/reveal host path helper definitions
- `notification`: native notification helper definitions
- `tray`: native tray icon lifecycle, tooltip/icon updates, flat context menus,
  and tray/menu events
- `global_hotkey`: global hotkey helper definitions
- `auto_launch`: startup-entry helper definitions
- `keepawake`: keep-awake helper definitions
- `microphone`: microphone discovery/capture helper definitions

## Tray Notes

The tray extension is backed by `justjavac/tray`, which owns the platform tray
native-stub. Proton native C stays limited to the CEF-backed runtime, windows,
and bridge ABI. The v1 API exposes `support`, `show`, `hide`, `setIcon`,
`setTooltip`, `setMenu`, and `destroy`.

Tray menus are flat. Supported item kinds are `normal`, `separator`, and
`checkbox`; nested submenus remain outside the Proton v1 surface. Native tray
events are pumped by the extension and forwarded as extension events named
`click`, `rightClick`, `doubleClick`, and `menuItemClick`.

Windows is the baseline for tray-icon click, right-click, and double-click
events. Menu item clicks are the portable event path across Windows, Linux, and
macOS when the desktop backend supports menu activation. Linux support depends
on GTK 3 plus AppIndicator or Ayatana AppIndicator being available in the
desktop session.
