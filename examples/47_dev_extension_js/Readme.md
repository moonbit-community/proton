# Dev Extension JS With Vite

Smoke example for extension JavaScript injection on frontend dev-server pages.

```powershell
cd examples
pushd 47_dev_extension_js/frontend
npm install
popd
proton_cli dev --package 47_dev_extension_js
```

When running the CLI directly from this repository instead of an installed
`proton_cli`, keep the Proton CLI cwd at the repository root:

```powershell
$repo = (Resolve-Path ..).Path
moon -C ..\cli run . -- -C $repo dev --package examples/47_dev_extension_js
```

The CLI discovers the package-local `moon.proton`, injects it into the app as
`PROTON_CONFIG_PATH`, uses `frontend.before_dev` to start Vite from the
configured `frontend.path`, then Proton opens `frontend.dev_url` with
`PROTON_DEV=1`. The Vite page receives `window.__MoonBit__.ticker` from native
bridge injection; it does not load a Proton script manually.

For a production build:

```powershell
cd examples
proton_cli build --package 47_dev_extension_js
```

`proton_cli build` runs `frontend.before_build`, validates
`frontend/dist/index.html`, then builds the native MoonBit app. In production
the app loads that Vite output through Proton's `proton://` asset route.

The repository E2E suite runs the same route through the local CLI:

```powershell
cd ..
moon -C e2e test -p justjavac/proton/e2e/test --target native `
  --no-parallelize --filter '*47_dev_extension_js*'
```

The test overrides the dev command to use a temporary Vite port, passes an
isolated Moon target directory through the local CLI, and then exercises the
production `proton_cli build` route. If `node_modules` is missing, the test
installs the locked frontend dependencies and removes test-owned dependencies
and build output after the run.
