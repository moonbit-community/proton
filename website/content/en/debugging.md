# Running and debugging

[中文](zh/debugging.html)

Frontend rendering, command handling, and native startup fail in different places. Start by identifying which part failed, then inspect that layer.

## Run the development application

From the directory containing `proton.project.json`:

```sh
proton_cli doctor
proton_cli dev
```

Doctor checks configuration, toolchain, runtime, and helper availability without changing the project. If it reports a missing runtime, run `proton_cli cef setup`.

With the minimal template, stop and rerun the app after editing the embedded page or backend. With isomorphic, Warren serves the frontend; frontend refresh behavior comes from that tool. Restart the native app after changing native backend code.

When an existing frontend server owns the configured port, either stop it or intentionally use `proton_cli dev --no-frontend`. Do not leave several dev commands competing for one endpoint.

## Open browser developer tools

To verify the inspector without relying on platform shortcuts, use this complete **`app/main.mbt`** in a minimal project:

```moonbit
///|
async fn main {
  @proton.html("Debugging", "<h1>Inspect this page</h1>", debug=true)
  .load_config()
  .window_lifecycle(
    on_ready=context => { context.handle().browser().open_devtools() },
    on_close=_ => (),
  )
  .run_or_abort()
}
```

Start it with `proton_cli dev`. The ready callback opens DevTools for the main browser. Use the Elements panel for the DOM and CSS, and Console for frontend exceptions. Remove this automatic inspector hook when you finish debugging.

In an existing application, keep its lifecycle logic and add the `open_devtools()` call to its ready handler rather than replacing the handler.

## Diagnose command failures

- **Bridge unavailable:** the page is probably in a regular browser. Open it through Proton.
- **Unknown/unavailable operation:** confirm the backend binds the command or grants the extension capability.
- **Decode failure:** compare the serialized field names and types with the request/response contract.
- **Business rejection:** inspect the response data, such as `InvalidTitle`, instead of treating it as a transport error.

Keep frontend catch/failure callbacks visible during debugging. Read backend terminal output for the operation's detailed error.

## Read application logs

Proton uses `tonyfettes/xlog`. Development output goes to stderr; packaged applications write to their platform log directory. Application categories use `app.*`; the framework uses `proton.*`.

Set `MOON_XLOG` in the process environment to adjust xlog filtering. Proton preserves application level and category settings. `PROTON_LOG_OUTPUT=stderr` is useful when launching a packaged app from a terminal; file output requires packaged metadata.

CEF's internal logs are separate and disabled by default. Use `PROTON_CEF_LOG` only when investigating Chromium/runtime behavior, not as the normal application logging interface.

## Check before reporting

For minimal, run `moon check --target native`. For isomorphic, run `moon check --target js,native`. Include the exact command, full error, Proton version, MoonBit version, OS/architecture, and whether the failure occurs in development or only after packaging.

A successful browser preview does not verify native commands. A successful build does not verify a packaged app. Reduce the reproduction to the failing layer before opening an [issue](https://github.com/moonbit-community/proton/issues).
