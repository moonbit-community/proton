# Minimal application

This example starts a native window from an inline HTML string. It shows the smallest application entry point: select page content, assign an application identifier, and run the application.

[01_run](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/01_run) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/51a88c4c0892ff9628e5795fc598d05262e96daa/examples/01_run/main.mbt)

## Behavior

A single 800 × 600 window displays “01 run”. The builder declares identity and starts the application.

```moonbit
///|
async fn main {
  let html =
    #|<!doctype html>
    #|<html>
    #|  <head><meta charset="utf-8"><title>01 run</title></head>
    #|  <body><h1>01 run</h1></body>
    #|</html>
  @proton.html("01 run", html, width=800, height=600, debug=true)
  .identifier("dev.proton.01-run")
  .run_or_abort()
}
```

## Implementation

The HTML is a MoonBit value passed directly to the application builder. No frontend server, asset lookup or command bridge is needed for this page. The explicit identifier supplies application identity for direct repository execution; a scaffold instead obtains it with load_config().

Reuse this form for a small self-contained page. Move to an asset entry when the page needs independently built CSS/JavaScript files. `debug=true` is an example choice, not a distribution requirement.

## Run

After completing [source checkout and runtime setup](../introduction/installation.md#source-checkout-and-runtime), run from the repository root:

```sh
moon -C examples run 01_run --target native
```

## Limits and interpretation

Use this to isolate runtime setup from frontend tooling. There is no command bridge or external resource loading in the example.
