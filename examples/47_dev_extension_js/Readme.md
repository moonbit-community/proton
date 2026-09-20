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

The CLI reads the package-local `proton.project.json`, uses
`frontend.before_dev` to start Vite from the configured `frontend.path`, then
overrides the code-declared asset entry with `frontend.dev_url` in development.
The Vite page receives `window.__MoonBit__.ticker` from native
bridge injection; it does not load a Proton script manually.

For a production build:

```powershell
cd examples
proton_cli build --package 47_dev_extension_js
```

`proton_cli build` runs `frontend.before_build`, validates
`frontend/dist/index.html`, then builds the native MoonBit app. In production
the app loads that Vite output through Proton's `proton://` asset route.
