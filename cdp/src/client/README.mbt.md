# justjavac/cdp/client

High-level Chrome DevTools Protocol client helpers for discovery, WebSocket
connections, command dispatch, event buffering, target management, and browser
launching.

## Use

```mbt nocheck
let target = @client.parse_cdp_target("9222")
let browser = @client.connect_cdp_browser_target(target)
defer browser.close()

let response = browser.send_schema_command("Browser.getVersion")
println(@client.cdp_response_result_json(response).stringify())
```

For page-level commands:

```mbt nocheck
let page = @client.connect_cdp_page_target(@client.parse_cdp_target("9222"))
defer page.close()

let response = page.send_schema_command(
  "Runtime.evaluate",
  params={
    "expression": "1 + 1",
    "returnByValue": true,
  },
)
println(@client.cdp_response_result_json(response).stringify())
```
