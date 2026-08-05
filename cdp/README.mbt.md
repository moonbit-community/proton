# justjavac/cdp

![Non-generated library coverage](https://img.shields.io/badge/non--generated%20library%20coverage-100%25-brightgreen.svg)

MoonBit library for the Chrome DevTools Protocol (CDP).

## Packages

- `justjavac/cdp/protocol`: CDP wire types, bundled manifest, schema
  validation, remote schema diff.
- `justjavac/cdp/protocol/typed`: generated params, command builders, event
  builders, result decoders.
- `justjavac/cdp/client`: discovery, WebSocket client, events, targets,
  browser launch helpers.

## Minimal Use

```mbt nocheck
let target = @client.parse_cdp_target("9222")
let browser = @client.connect_cdp_browser_target(target)
defer browser.close()

let response = browser.send_schema_command("Browser.getVersion")
println(@client.cdp_response_result_json(response).stringify())
```

For page domains:

```mbt nocheck
let page = @client.connect_cdp_page_target(@client.parse_cdp_target("9222"))
defer page.close()
```
