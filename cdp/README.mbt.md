# moonbit-community/proton_cdp

![Non-generated library coverage](https://img.shields.io/badge/non--generated%20library%20coverage-100%25-brightgreen.svg)

MoonBit library for the Chrome DevTools Protocol (CDP).

## Packages

- `moonbit-community/proton_cdp/protocol`: CDP wire types, bundled manifest, schema
  validation, remote schema diff.
- `moonbit-community/proton_cdp/protocol/typed`: generated params, command builders, event
  builders, result decoders.
- `moonbit-community/proton_cdp/client`: discovery, WebSocket client, events, targets,
  browser launch helpers.
- `moonbit-community/proton_cdp/page`: context-aware page evaluation and navigation.

## Minimal Use

```mbt nocheck
let target = @client.parse_cdp_target("9222")
@async.with_task_group(fn(tasks) {
  let browser = @client.connect_cdp_browser_target(tasks, target)
  defer browser.close()
  let response = browser.send_schema_command("Browser.getVersion")
  println(@client.cdp_response_result_json(response).stringify())
})
```

For page domains:

```mbt nocheck
@async.with_task_group(fn(tasks) {
  let page = @page.Page::connect(
    tasks,
    @client.parse_cdp_target("9222"),
  )
  defer page.close()
  println(page.evaluate("document.title").stringify())
})
```
