# Events and targets

This page covers CDP events, event handlers, and browser-level target sessions.

## Handle events

Events received while waiting for responses are buffered.

```mbt nocheck
ignore(page.send_schema_command("Runtime.enable"))
let event = page.recv_cdp_event(method_name="Runtime.executionContextCreated")
println(event.method_name)
```

You can inspect buffered events later:

```mbt nocheck
let events = page.cdp_events(method_name="Runtime.consoleAPICalled")
println(events.length())
```

You can also register a synchronous handler:

```mbt nocheck
let handler_id = page.on_cdp_event(
  method_name="Runtime.consoleAPICalled",
  event => {
    println(event.method_name)
  },
)

ignore(page.remove_cdp_event_handler(handler_id))
```

Handlers run when the client records incoming events. They should stay small and
avoid long blocking work.

## Use target sessions

Use browser-level Target commands to create or attach to targets:

```mbt nocheck
let browser = @client.connect_cdp_browser_target(@client.parse_cdp_target("9222"))
defer browser.close()

let target_id = browser.create_target(url="https://example.com/")
let session_id = browser.attach_to_target(target_id, flatten=true)
```

Pass `session_id` when sending commands through a flattened session:

```mbt nocheck
ignore(browser.send_schema_command("Runtime.enable", session_id=session_id))
```

The client tracks `Target.attachedToTarget`, `Target.detachedFromTarget`, and
`Inspector.detached` events in its attached-target cache.
