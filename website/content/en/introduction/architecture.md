# Architecture & processes

A Proton app has a native host and a web frontend. Even when both are written in MoonBit, they run in different environments and communicate through messages.

## The native host

The backend is a MoonBit executable. It starts Proton, owns native windows, registers command handlers, and accesses operating-system features.

Put authoritative application state here when it must be shared across windows or validated independently of the UI. In the Todo template, the backend owns the Todo list and revision; the frontend owns the current input text and loading/error display.

The backend uses `moonbitlang/async`. Proton integrates its native event loop with that scheduler during initialization. Application code calls `.run()` or `.run_or_abort()`; it does not create a second UI polling loop.

## The web frontend

Chromium renders HTML, CSS, and JavaScript. Rabbita compiles MoonBit UI code to JavaScript for this environment. A frontend variable is not a reference to a backend value, even when the types come from one shared module.

CEF manages renderer and other subprocesses through the release-matched helper. Seeing several processes while an application runs is normal. Keep lifecycle management with Proton so shutdown can finish normally.

## Commands and events

A **command** sends a request to a registered backend handler and returns a result or failure. Use it when the caller needs an answer: load a document, create a Todo, or query a snapshot.

An **event** sends a notification to a listening frontend. Use it to announce a change or progress. It is not a durable queue and does not recover notifications missed before subscription.

```text
Frontend                 Native backend
   | -- command(request) --> |
   | <-- response/failure -- |
   |                         |
   | <-- event(payload) ---- |
```

The `proton_contract` package describes routes and payload types. `proton_client` calls them from a MoonBit frontend; `proton_rabbita` connects requests/subscriptions to Rabbita components. Plain JavaScript can use the injected bridge, as shown in [calling the backend](commands-events.md).

Sharing a type does not share memory. Values cross the bridge as serialized data. Keep payloads focused on what the receiver needs.

## Capabilities

Application commands expose your business operations. Extensions expose reusable host features such as filesystem access. A capability both installs an extension's backend and grants access to selected renderer targets.

The default target is the main entry. A second window does not automatically need all the same permissions. Configure the operations, roots, and targets according to the feature you are building; see [native capabilities](capabilities.md).

## Development and distribution

With inline HTML, the backend carries the page string. With a frontend tool, `proton_cli dev` starts its server and uses its development URL. An ordinary browser can preview that URL, but it does not contain Proton's native bridge.

A production build generates static frontend assets. Packaging combines those assets, the backend executable, Chromium, and the matching helper. This is why a successful frontend preview is not a full application test, and why distributing only the backend executable is insufficient.
