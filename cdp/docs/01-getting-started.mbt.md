# Getting started

This page covers the minimum setup needed to connect `justjavac/cdp` to a
Chrome-family browser with remote debugging enabled.

## Requirements

- MoonBit with native target support.
- `moonbitlang/async`.
- Chrome, Edge, or Chromium when using a real browser.

For local development in this repository:

```bash
moon install
moon test
```

## Package imports

For an executable package that connects to CDP:

```moonbit
import {
  "moonbitlang/async",
  "justjavac/cdp/client",
  "justjavac/cdp/protocol",
  "justjavac/cdp/protocol/typed",
}

supported_targets = "+native"
```

Use only the packages you need. For example, a discovery-only tool usually
needs only `client`.

## Start Chrome with remote debugging

Start Chrome manually:

```bash
chrome --remote-debugging-port=9222 --user-data-dir=/tmp/mbt-cdp-profile
```

PowerShell example:

```powershell
& "C:\Program Files\Google\Chrome\Application\chrome.exe" `
  --remote-debugging-port=9222 `
  --user-data-dir="$env:TEMP\mbt-cdp-profile"
```

Use a separate profile directory for CDP work. Do not point automated tests at
your daily browser profile.

## Parse a target

`parse_cdp_target` accepts common remote debugging target forms:

- `9222`
- `127.0.0.1:9222`
- `http://127.0.0.1:9222`
- `ws://127.0.0.1:9222/devtools/browser/<id>`
- `ws://127.0.0.1:9222/devtools/page/<id>`

```mbt nocheck
let target = @client.parse_cdp_target("9222")
```

Port and HTTP targets are resolved through Chrome's discovery endpoints.
WebSocket targets can be connected directly when no extra page selection is
needed.

## Discover browser metadata

Use `/json/version` to discover browser metadata and the browser-level
WebSocket URL:

```mbt nocheck
let target = @client.parse_cdp_target("9222")
let version = @client.discover_version(target)
println(version.browser)
println(version.protocol_version)
println(version.web_socket_debugger_url)
```

The browser-level WebSocket is the right endpoint for `Browser.*` and
`Target.*` commands.

## Connect to the browser

```mbt nocheck
let target = @client.parse_cdp_target("9222")
let client = @client.connect_cdp_browser_target(target)
defer client.close()

let response = client.send_schema_command("Browser.getVersion")
let result = @client.cdp_response_result_json(response)
println(result.stringify())
```

`send_schema_command` validates the method, parameters, and successful result
shape against the bundled protocol manifest.

## Connect to a page

To work with page domains such as `Runtime`, `Page`, `DOM`, and `Network`,
connect to a page-level target:

```mbt nocheck
let target = @client.parse_cdp_target("9222")
let page = @client.connect_cdp_page_target(target)
defer page.close()
```

You can select a page by target id, URL, or title:

```mbt nocheck
let page = @client.connect_cdp_page_target(
  target,
  url="https://example.com/",
)
```

When no selector is provided, the first discovered page target is used.
