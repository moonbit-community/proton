# Extensions

`moonbit-community/proton_ext` contains Proton extension packages for the
source-built native route. Generated app-command extensions expose host
capabilities through the Proton bridge and keep metadata for catalog/codegen
validation.

The current supported route is:

```text
MoonBit app -> moonbit-community/proton -> private native stubs -> command bridge
```

Applications add typed extension capabilities with `.capability(...)`. One
capability installs its backend implementation and grants its validated scope
to the selected renderer targets; these two decisions cannot drift apart.
Omitted capabilities are unavailable and do not prevent startup. Inline HTML
entries can call granted proxies through `window.__MoonBit__.<namespace>` or
the low-level `window.__MoonBit__.core.invokeOp(...)` bridge, depending on the
extension and example. Pages subscribe to events through either
`window.__MoonBit__.events.on(...)` or `window.__MoonBit__.<namespace>.on(...)`.

Application commands registered with `.commands(...)` are exposed to the
primary configured entry by default under `window.__MoonBit__.app`, one proxy
per registered command:

```js
await window.__MoonBit__.app.ping({ value: 1 });
await window.__MoonBit__.app["devtoys.fs.stat"]({ path: "/tmp" });
await window.__MoonBit__.app.invoke("ping", { value: 1 });
```

Application events are delivered through `window.__MoonBit__.app.on`, which
returns an unsubscribe function:

```js
const stop = window.__MoonBit__.app.on("changed", ({ name, payload }) => {
  console.log(name, payload);
});
```

Application events are keyed by route only, so they never reach the
`window.__MoonBit__.events.on(...)` name table that carries extension events.
Without that separation an application event named `add.finished` would be
delivered to listeners registered for extension `add`'s `finished` event, which
carries a different payload shape. `events.onJson("app:changed", ...)` still
receives the raw payload text.

`invokeOp` is the transport-level entry point and takes the fully qualified
route: `app:<name>` for application commands and `ext:<namespace>/<name>` for
extension commands. Prefer the proxies above, which build the route for you.
A request for an unavailable route is rejected by the bridge. A route granted
to another renderer target is rejected for the calling page.

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
- `power_monitor`: power, idle, and session-event helper definitions
- `screen_monitor`: display queries, cursor position, and display-topology events

## Extension Metadata

Extension metadata is used by code generation, catalog checks, dependency
planning, and generated command bridge packages. Applications grant renderer
capabilities with typed builders in top-level Proton code.
`proton.project.json` is CLI-only and does not expose capabilities.

## Tray Notes

The tray extension is backed by `moonbit-community/proton_tray`, which owns the platform tray
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
