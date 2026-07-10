# Dev Extension JS With Vite

Smoke example for extension JavaScript injection on frontend dev-server pages.

```powershell
cd examples
pushd 47_dev_extension_js/frontend
npm install
popd
proton_cli dev 47_dev_extension_js
```

When running the CLI directly from this repository instead of an installed
`proton_cli`, keep the Proton CLI cwd at the repository root:

```powershell
$repo = (Resolve-Path .).Path
moon -C cli run . -- -C $repo dev examples/47_dev_extension_js
```

The CLI discovers the package-local `moon.proton`, injects it into the app as
`PROTON_CONFIG_PATH`, uses `frontend.before_dev` to start Vite from the
configured `frontend.cwd`, then Proton opens `frontend.dev_url` with
`PROTON_DEV=1`. The Vite page receives `window.__MoonBit__.ticker` from native
bridge injection; it does not load a Proton script manually.

For a production build:

```powershell
cd examples
proton_cli build 47_dev_extension_js
```

`proton_cli build` runs `frontend.before_build`, validates
`frontend/dist/index.html`, then builds the native MoonBit app. In production
the app loads that Vite output through Proton's `proton://` asset route.

The repository smoke test runs the same route through the local CLI:

```powershell
node scripts/e2e_bridge_smoke.mjs 47_dev_extension_js
```

The smoke test overrides the dev command to use a temporary Vite port, then
uses the local `proton_cli build` route for the production check. If
`node_modules` is missing, the smoke test installs the locked frontend
dependencies and removes them after the run.
