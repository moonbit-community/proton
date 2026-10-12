# moonbit-community/proton_cdp

An optional native MoonBit library for automating Proton and other Chromium-based
applications through the Chrome DevTools Protocol (CDP). It does not depend on
Proton's runtime or CEF. Applications do not need this package to open DevTools.

## Install

In a separate automation project:

```sh
moon add moonbit-community/proton_cdp
moon add moonbitlang/async
```

The network client and page helpers support the **native** target on macOS,
Linux, and Windows. A browser with remote debugging enabled must be running.

Add these imports to the executable's `moon.pkg`:

```moonbit
import {
  "moonbitlang/async",
  "moonbitlang/core/env",
  "moonbit-community/proton_cdp/client",
  "moonbit-community/proton_cdp/page",
}
supported_targets = "+native"
options(is_main: true)
```

## Connect to a Proton application

Enable debugging with `App.debug()` and launch the application with
`PROTON_REMOTE_DEBUGGING_PORT=0`. Chromium chooses a free port and prints:

```text
DevTools listening on ws://127.0.0.1:<port>/devtools/browser/<id>
```

The environment variable only selects the port; it does not enable debugging
when the app's debug setting is disabled. Use the announced endpoint for that
process lifetime.

Save the following as `main.mbt` in the automation project:

```mbt nocheck
///|
async fn main {
  @async.with_task_group(tasks => {
    let page = @page.Page::connect(tasks, @client.parse_cdp_target(@env.args()[1]))
    println(page.evaluate("document.title").stringify())
  })
}
```

Run it with the endpoint printed by the application:

```sh
moon run . --target native -- 'ws://127.0.0.1:<port>/devtools/browser/<id>'
```

`Page.connect` selects a page target. For multiple pages, pass `target_id`, `url`,
or `title` to select one. Connections belong to the supplied task group; leaving
its scope closes them, without terminating the application. `Page.capture_png()`
returns a base64-encoded PNG screenshot.

## Packages

| Package | Purpose |
| --- | --- |
| `proton_cdp/client` | Endpoint discovery, WebSocket connections, events, targets, browser launch |
| `proton_cdp/page` | Page evaluation, navigation, screenshots, isolated worlds |
| `proton_cdp/protocol` | Wire types, bundled schema validation, remote schema comparison |
| `proton_cdp/protocol/typed` | Generated command parameters, builders, result decoders |

All package names use the `moonbit-community/` prefix.

## Protocol compatibility

The typed API follows the bundled schema snapshot, not every version of Chrome.
CDP's `1.3` version field does not identify a Chromium release. Commands and fields
may differ between target browsers, especially experimental APIs; an unsupported
command returns an error rather than being emulated.

Proton's E2E suite exercises this library against the Chromium runtime shipped
with the same Proton release. This is coverage of the exercised operations, not
of every generated command. Other Chromium-based browsers can expose different
capabilities. See [schema provenance and command modes](docs/02-commands-and-schemas.mbt.md).

See the [full guide](docs/README.mbt.md) for discovery, events, and browser launch.

## License

Apache-2.0. See [LICENSE](LICENSE).
