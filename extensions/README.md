# Extensions

`justjavac/proton_ext` contains Proton extension packages for the native DLL
route. Generated app-command extensions expose host capabilities through the
Proton bridge and keep metadata for catalog/codegen validation.

The current supported route is:

```text
MoonBit app -> justjavac/proton -> proton dynamic library -> command bridge
```

Applications register extensions with `.extension(...)`. Inline HTML entries
can call generated proxies through `window.__MoonBit__.<namespace>` or the
low-level `window.__MoonBit__.core.invokeOp(...)` bridge, depending on the
extension and example. Pages subscribe to events through either
`window.__MoonBit__.events.on(...)` or `window.__MoonBit__.<namespace>.on(...)`.

## Packages

- `fs`: host filesystem helper definitions
- `path`: path transform helper definitions
- `dialog`: native dialog helper definitions
- `clipboard`: clipboard helper definitions
- `shell`: open/reveal host path helper definitions
- `notification`: macOS system notifications and notification-click events
- `tray`: native tray icon lifecycle, tooltip/icon updates, flat context menus,
  and tray/menu events
- `global_hotkey`: global hotkey helper definitions
- `auto_launch`: startup-entry helper definitions
- `keepawake`: keep-awake helper definitions
- `microphone`: microphone discovery/capture helper definitions

## Extension Metadata

Extension metadata is used by code generation, catalog checks, dependency
planning, and generated command bridge packages. Applications should register
extensions in top-level Proton code with `.extension(...)`; `moon.proton`
extension settings are not the active configuration surface.

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

## Notification Notes

The notification extension owns its macOS `UNUserNotificationCenter` delegate;
the Proton engine does not expose notification-specific ABI. `show` accepts an
optional string payload, and clicks are pumped into `notification.click`
events. macOS notifications require a packaged app bundle with a bundle
identifier. Windows and Linux backends remain unimplemented.
