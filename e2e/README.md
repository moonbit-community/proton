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
moon -C e2e test -p moonbit-community/proton/e2e/test \
  --target native --no-parallelize --diagnostic-limit 200
```

Keep the package filter and `--no-parallelize`: E2E tests own native processes,
CDP ports, frontend servers, and runtime logs. The tests resolve the required
CEF runtime from the immutable user-wide store. Each isolated scenario installs a release helper
from the same Proton source as the application through `moon install --path`.
The suite covers:

- `38_async_extension_add`, `39_sync_async_extensions`, and
  `42_attribute_codegen_commands` command-extension proxies;
- `40_event_broadcast` event delivery and reload isolation;
- `41_app_commands` bridge guards, queue saturation, screenshot/OSR paint,
  non-Proton origins, and pending-request cleanup;
- `45_bridge_multi_window` routing, distinct targets/handles, and close
  lifecycle;
- `46_asset_sidecar_resources` HTML/CSS/JS sidecars and generated proxies;
- `47_dev_extension_js` CLI/Vite dev startup, reload, non-Proton origins,
  production asset routing, and frontend dependency/build cleanup.

The executable driver is useful when an application is already running with
remote debugging enabled:

```sh
MBT_PROTON_E2E_SCENARIO=41_app_commands MBT_CDP_TARGET=9222 moon -C e2e run test --target native
```

For the Vite scenario, the driver expects a loopback HTTP page whose frontend
has set the `#bridge-status` readiness marker. The self-hosted suite starts the
frontend itself and cleans up test-owned dependencies and build output.

The headless path uses CEF windowless rendering (OSR). It does not create a
hidden native top-level window and does not enable Chromium's `--headless`
switch. Set `PROTON_HEADLESS=1` in the app environment; the self-hosted suite
does this automatically.

The current Linux engine still initializes GTK/X11. Run the same probe under a
virtual X server when no display is available:

```sh
xvfb-run -a moon -C e2e test -p moonbit-community/proton/e2e/test \
  --target native --no-parallelize --diagnostic-limit 200
```
