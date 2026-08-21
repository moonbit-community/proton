# moonbit-community/proton_cdp/client

High-level Chrome DevTools Protocol client helpers for discovery, WebSocket
connections, command dispatch, event observation, target management, and browser
launching.

## Use

```mbt nocheck
let target = @client.parse_cdp_target("9222")
@async.with_task_group(fn(tasks) {
  let browser = @client.connect_cdp_browser_target(tasks, target)
  let response = browser.send_schema_command("Browser.getVersion")
  println(@client.cdp_response_result_json(response).stringify())
})
```

Connections belong to the task group passed to `connect`; leaving that scope
cancels the reader and closes the WebSocket.

For page JavaScript execution, use the context-aware page API:

```mbt nocheck
@async.with_task_group(fn(tasks) {
  let page = @page.Page::connect(
    tasks,
    @client.parse_cdp_target("9222"),
  )
  println(page.evaluate("1 + 1").stringify())
})
```
