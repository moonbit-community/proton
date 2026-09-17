# Calling the backend

[中文](zh/commands-events.html)

A command lets frontend code ask the native backend to do work. This guide adds a working greeting form to the [minimal project](first-app.md). It uses plain JavaScript first so the native boundary is visible; the [Todo tutorial](isomorphic.md) uses shared MoonBit types and Rabbita.

## Add the contract dependency

In **`moon.mod`**, add this entry inside the existing `import { ... }` block, preserving the existing dependencies:

```text
"moonbit-community/proton_contract@0.2.11",
```

Replace **`app/moon.pkg`** with:

```text
import {
  "moonbitlang/core/json",
  "moonbitlang/async",
  "moonbit-community/proton",
  "moonbit-community/proton_contract",
}

supported_targets = "native"

pkgtype(kind: "executable")
```

Run `moon update` from the project root. A module dependency makes the library available; the package import makes `@proton_contract` usable in the entry.

## Define, register, and call a command

Replace **`app/main.mbt`** with this complete example:

```moonbit
///|
struct GreetRequest {
  name : String
} derive(FromJson, ToJson)

///|
let greet : @proton_contract.Command[GreetRequest, String] =
  @proton_contract.command("greet")

///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html lang="en">
    #|<meta charset="utf-8">
    #|<title>Greeting</title>
    #|<style>body { font: 18px system-ui; padding: 32px; }</style>
    #|<label>Name <input id="name" value="MoonBit"></label>
    #|<button id="greet">Greet</button>
    #|<p id="result" role="status"></p>
    #|<script>
    #|  document.querySelector("#greet").onclick = async () => {
    #|    const result = document.querySelector("#result");
    #|    try {
    #|      result.textContent = await window.__MoonBit__.app.greet({
    #|        name: document.querySelector("#name").value
    #|      });
    #|    } catch (error) {
    #|      result.textContent = String(error);
    #|    }
    #|  };
    #|</script>
    #|</html>
  @proton.html("Greeting", html)
  .load_config()
  .commands(fn(registrar) raise {
    registrar.bind(greet, (_context, request) => {
      "Hello, " + request.name + "!"
    })
  })
  .run_or_abort()
}
```

Run `proton_cli dev`. Enter “Ada” and click **Greet**. The page should display “Hello, Ada!”.

There are three connected parts:

1. `GreetRequest` describes the JSON request, and `greet` declares its route and response type.
2. `.commands(...)` registers a handler with `registrar.bind`. The handler receives the caller context and decoded request.
3. `window.__MoonBit__.app.greet(...)` returns a JavaScript promise for the response. The page awaits it and handles rejection.

Declaring a descriptor alone does not register a handler. Keep command names unique within the application.

## Arguments and return values

The object property `name` matches the request field. Add serializable fields to the request when an operation needs more input. Results can be strings, numbers, arrays, or structs with `ToJson`.

The native handler executes in the backend. It is the right place for business validation or native operations; the renderer does not directly call arbitrary MoonBit functions.

## Errors

A malformed request, unknown command, or handler failure rejects the JavaScript promise. Keep the `try/catch` around the call and show a useful message.

Expected business outcomes should be response data. For example, the Todo template returns `Changed`, `InvalidTitle`, or `MissingTodo`. Its frontend handles these separately from `ClientFailure`, which describes bridge, transport, and decoding failures.

Do not assume a request succeeded just because the frontend button handler ran. Wait for its result before updating UI that depends on successful completion.

## Async work and caller context

Command handlers can perform async work. The context identifies the caller and can send a typed event to it; [sending events to the frontend](events.md) extends this exact example.

If the page opens in a normal browser, `window.__MoonBit__` is absent. Start the desktop app with `proton_cli dev`, not just the frontend URL.
