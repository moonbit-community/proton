# Minimal application

[中文](../zh/examples/01_run.html)

Inline HTML and a native application entry point.

[01_run](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/01_run) · Source files: [main.mbt](https://github.com/moonbit-community/proton/tree/25d77e6236420025ddf1ab04995c0c2a05bba9ed/examples/01_run/main.mbt)

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

## Run

[Environment requirements](../introduction/installation.md) apply. From the checked-out repository root:

```sh
moon -C examples run 01_run --target native
```

## Limits and interpretation

Use this to isolate runtime setup from frontend tooling. There is no command bridge or external resource loading in the example.
