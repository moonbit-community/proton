# Extensions

`moonbit-community/proton_ext` contains Proton extension packages for
native desktop applications. Extensions expose host capabilities through the
Proton bridge.

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

Application events use `window.__MoonBit__.app.on(...)`; extension events use
`window.__MoonBit__.events.on(...)`. `events.onJson("app:changed", ...)` receives
the raw payload text.

`invokeOp` is the transport-level entry point and takes the fully qualified
route: `app:<name>` for application commands and `ext:<namespace>/<name>` for
extension commands. Prefer the proxies above, which build the route for you.
A request for an unavailable route is rejected by the bridge. A route granted
to another renderer target is rejected for the calling page.

## Defining an extension

Pass the extension contract and one registration callback to
`@proton_extension.typed(contract, register)`. Bind typed command descriptors
inside that callback with `registrar.bind(command, handler)`. Proton derives
frontend proxies and permission operation names from those successful bindings;
there is no separate command-route list. The callback runs once during startup,
before extension start hooks. Foreign commands and duplicate bindings fail
registration, and the registrar cannot be used after the callback returns.

Reuse the same extension definition when granting different scopes or renderer
targets. Independent definitions with the same extension ID are rejected, even
if they use the same command names. Built-in extensions without per-definition
state share their definition across `capability()` calls. For the process
extension, reuse one returned capability across targets to share its process
owner.

## Packages

- `fs`: host filesystem helper definitions
- `path`: path transform helper definitions
- `dialog`: native message, error, confirmation, and file dialogs
- `clipboard`: read, write, and clear plain text in the system clipboard
- `shell`: open/reveal host path helper definitions
- `notification`: macOS system notifications and notification-click events
- `tray`: native tray icon lifecycle, tooltip/icon updates, flat context menus,
  and tray/menu events
- `global_hotkey`: register, unregister, inspect, clear, and receive global hotkeys
- `auto_launch`: startup-entry helper definitions
- `keepawake`: keep-awake helper definitions
- `microphone`: microphone discovery/capture helper definitions
- `power_monitor`: power, idle, and session-event helper definitions
- `screen_monitor`: display queries, cursor position, and display-topology events
- `desktop_capturer`: screen-source enumeration for Electron-style desktop capture flows
- `net`: typed renderer-to-host HTTP requests with response status, headers, and body
- `process`: spawn child processes and wait for or terminate them in later requests

## Process lifetime

Children spawned through the process extension belong to that extension's
application lifetime, so returning from `spawn` does not terminate them.
`wait` collects the exit status and removes the process handle; `kill` terminates
the child and leaves its handle available for `wait`. Application shutdown cancels
and reaps remaining children, then clears the extension's process registry.

## Tray Notes

The tray API exposes `support`, `show`, `hide`, `setIcon`,
`setTooltip`, `setMenu`, and `destroy`.

Tray menus are flat. Supported item kinds are `normal`, `separator`, and
`checkbox`; nested submenus remain outside the Proton v1 surface. Tray
events are named `click`, `rightClick`, `doubleClick`, and `menuItemClick`.

Windows is the baseline for tray-icon click, right-click, and double-click
events. Menu item clicks are the portable event path across Windows, Linux, and
macOS when the desktop backend supports menu activation. Linux support depends
on GTK 3 plus AppIndicator or Ayatana AppIndicator being available in the
desktop session.

## Notification Notes

`show` accepts an optional string payload, and clicks produce
`notification.click` events. macOS notifications require a packaged app bundle with a bundle
identifier. Windows and Linux backends remain unimplemented.

## Monitor availability

The `power_monitor` and `screen_monitor` packages expose `watch_status()`:
`Stopped` before startup or after cleanup, `Watching` after native registration,
and `Unavailable(reason)` when monitor creation or watching fails. Watch failure
is best-effort and does not disable working query commands. Queries do not
clear the retained watch error or automatically retry an existing monitor.
Screen topology events carry the affected display's snapshot; removal carries
the previous snapshot, even when there is no remaining primary display.
