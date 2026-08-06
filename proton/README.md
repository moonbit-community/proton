# moonbit-community/proton

MoonBit facade for building Proton desktop applications on the native runtime.
This package is the public app surface: windows, entries, commands, events, and
lifecycle hooks are all configured from MoonBit code. For the full development
workflow — scaffolding, CEF runtime setup, dev mode, and packaging — see the
[repository README](../README.md) and the `proton_cli` tool.

## Quick example

```moonbit
async fn main {
  @proton.install_event_loop()
  @proton.html("Hello", "<h1>Hello</h1>").run_or_abort()
}
```

`@proton.install_event_loop` hands Proton's event loop to `moonbitlang/async`,
which then keeps every line of MoonBit on the main thread and moves only its own
waiting to a thread of its own. It must be the first statement of `async fn
main`, before any other async work, and the package must import
`moonbitlang/async` for `async fn main` to be available at all. `@proton.html`
accepts optional `width?`, `height?`, `debug?`, and `resizable?` arguments.

## Entry points

- `@proton.html(title, html, ...)` — inline HTML document.
- `@proton.url(title, url, ...)` — a remote or local URL.
- `@proton.file(title, path, ...)` — an HTML file on disk.
- `@proton.asset(title, path, ...)` — an HTML asset shipped with the app.
- `@proton.config("moon.proton")` — an app described by a `moon.proton` file.
- `@proton.app()` — config from `PROTON_CONFIG_PATH`, `moon.proton` in the
  current working directory, or code-only defaults.

## Commands and events

Register typed commands on the app builder:

```moonbit
@proton.config("moon.proton")
.commands(fn(registrar) raise { registrar.bind(ping_command, ping) })
.run_or_abort()
```

`@proton.CommandRegistrar` binds contract command descriptors to async
handlers; each handler receives a `@proton.CommandContext` and the decoded
request payload. The backend emits events to the renderer with
`CommandContext::emit(event, payload)`. JavaScript invokes commands and
subscribes to events through the bridge installed on `window`: commands are
called by their contract operation name through `core.invokeOp`, and backend
events arrive on the `events` channel. For a contract with namespace `app`:

```js
const reply = await window.__MoonBit__.core.invokeOp("ext:app/ping", {
  name: "proton",
});
window.__MoonBit__.events.on("app.tick", (event) => console.log(event.payload));
```

Extensions built on `moonbit-community/proton_ext` additionally install namespaced
proxies such as `window.__MoonBit__.ticker.start(...)`.

## Windows

Add secondary windows to the app builder:

```moonbit
@proton.html("Main", main_html)
.add_window(
  "settings",
  "Settings",
  @proton.AppEntry::Html(settings_html),
  width=420,
  height=320,
)
```

The window id `"main"` is reserved for the primary window. The process exits
when all windows have closed.

## Headless mode

`.headless()` runs the app off-screen without creating a native window. Set
`PROTON_HEADLESS=1` to force headless mode for automated test runs.

## Learn more

- Runnable demos live in the repository's `examples/` directory.
- The CLI covers the project workflow: `proton_cli new`, `proton_cli cef setup`,
  `proton_cli dev`, `proton_cli build`, and `proton_cli package`.
