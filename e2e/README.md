# Proton E2E

CDP-based end-to-end tests for the source-built native bridge route.

The module is part of the root `moon.work`. Do not mutate the workspace before
running E2E tests.

## Self-update

`self_update/` installs a signed release of a signed application over itself and
restarts into it, on macOS. It is a script rather than a `moon test` scenario
because it needs `codesign`, `openssl` and a real installed bundle. See
[self_update/README.md](self_update/README.md).

## Self-hosted MoonBit E2E

The E2E executable runs the complete self-hosted suite directly. Each scenario selects
its own CDP port, starts the required application/runtime route in headless OSR
mode, performs typed CDP probes, closes Chromium through `Browser.close`, and
verifies that the application, helper process tree, and CDP endpoint stop:

```sh
moon -C cefsetup run . --target native
moon install moonbit-community/warren@0.3.3
moon -C e2e run test --target native --diagnostic-limit 200 -- --self-hosted
```

`moon -C e2e test test --target native` runs helper unit tests only; it does
not launch the self-hosted scenarios.

Run one suite at a time: E2E scenarios own native processes,
CDP ports, frontend servers, and runtime logs. The tests resolve the required
CEF runtime from the immutable user-wide store. Each isolated scenario installs a release helper
from the same Proton source as the application through `moon install --path`.
The suite covers:

- single-instance forwarding through the real application loop, followed by
  primary/secondary and CEF helper shutdown, plus a runtime lock release that
  lets the next launch become primary (`--single-instance`);
- the cancelable quit chain, forced exits, and process exit codes
  (`--quit-chain`);

- `38_async_extension_add`, `39_sync_async_extensions`, and
  `42_attribute_codegen_commands` command-extension proxies;
- `40_event_broadcast` event delivery and reload isolation;
- `41_app_commands` bridge guards, queue saturation, screenshot/OSR paint,
  non-Proton origins, and pending-request cleanup;
- `45_bridge_multi_window` routing, distinct targets/handles, and close
  lifecycle;
- `46_asset_sidecar_resources` HTML/CSS/JS sidecars and generated proxies;
- `47_dev_extension_js` CLI/Warren dev startup, reload, non-Proton origins,
  production asset routing, and frontend build cleanup.

The executable driver is useful when an application is already running with
remote debugging enabled:

```sh
MBT_PROTON_E2E_SCENARIO=41_app_commands MBT_CDP_TARGET=9222 moon -C e2e run test --target native
```

For the Warren scenario, the driver expects a loopback HTTP page whose frontend
has set the `#bridge-status` readiness marker. The self-hosted suite starts the
frontend itself and cleans up test-owned production output. Warren compiles the
MoonBit frontend without npm dependencies. Run this scenario
alone with:

```sh
moon -C e2e run test --target native -- --dev-extension
```

The headless path uses CEF windowless rendering (OSR). It does not create a
hidden native top-level window and does not enable Chromium's `--headless`
switch. Set `PROTON_HEADLESS=1` in the app environment; the self-hosted suite
does this automatically.

CDP controls Chromium content, not AppKit, Win32, or GTK system UI. Native
dialogs are therefore unavailable in headless mode and cannot be completed by
CDP. Tests for New, Open, and Save workflows should keep these boundaries
separate:

- exercise rendering, bridge commands, and dialog error handling through
  headless CDP;
- pass explicit temporary paths to backend file operations instead of opening a
  native picker;
- test renderer behavior after a selection with a fake dialog result; and
- keep a small headed platform test for displaying, completing, and cancelling
  real native dialogs. CDP may trigger the browser action, but platform UI
  automation or a human must operate the dialog itself.

The current Linux engine still initializes GTK/X11. Run the same probe under a
virtual X server when no display is available:

```sh
xvfb-run -a moon -C e2e run test --target native --diagnostic-limit 200 -- --self-hosted
```

## Lifecycle regressions

Run the public-API lifecycle regression scenarios without opening native windows:

```sh
moon -C e2e run test --target native -- --lifecycle-regressions
```

These scenarios cover closing a view before browser submission, stale view handles,
opening secondary windows from initial startup hooks, task cancellation, window task
failures, intercepted close decisions, and application-level control
(`is_ready`, `focus`, and the macOS AppKit group). The `process-events` case
also kills the renderer helpers of a running application to verify
`render-process-gone` while the session, window, and web contents creation
events are observed. The `app-metrics` case starts Chromium's task-manager
sampling, waits for the first measured footprint, and then asserts the reported
process types and the browser-first order. The runner also executes control
cases, requires explicit success markers, and checks application and helper
shutdown.
They are included in `--self-hosted`. Set `PROTON_E2E_LIFECYCLE_CASE` to a case name
from `test/lifecycle_regressions.mbt` to run one scenario.

## Quit event chain

Run the isolated quit-chain probe, which starts one headless application per
case, releases the quit request through a gate file, and asserts the recorded
chain steps and the process exit status:

```sh
moon -C e2e run test --target native -- --quit-chain
```

The probe requires `on_before_quit` -> `on_will_quit` -> `on_quit` for orderly
quits with exit code `0` and `3`, requires a forced exit to skip the cancelable
steps while still reporting `quit 7`, and requires a prevented `before-quit` or
`will-quit` to leave the application running.

## Dev-extension failure diagnostics

The Warren scenario reports startup, page/reload/origin probes, build, and
shutdown separately. Startup uses the command timeout, builds have a minimum
180-second budget on slow platforms, development page probes receive three
probe budgets, and shutdown retains its own deadline. Helper installation has
a minimum 180-second build budget. There is no single probe-sized deadline
covering compilation and all subsequent phases.

Successful runs remove their temporary directory. Failed runs retain child
logs and `failure.txt`, print the directory, and expose it to CI for artifact
upload. Runtime failures include the active phase, child PID/status, process
tree and a bounded log tail.
