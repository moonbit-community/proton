# Dev Extension JS With Warren

Smoke example for extension JavaScript injection into a MoonBit frontend served
and built by Warren. The frontend has no npm dependencies.

```powershell
moon install moonbit-community/warren@0.3.2
proton_cli -C . dev --config examples/47_dev_extension_js/proton.project.json
```

When running the CLI directly from this repository instead of an installed
`proton_cli`, keep the Proton CLI cwd at the repository root:

```powershell
$repo = (Get-Location).Path
moon -C cli run . -- -C $repo dev --config examples/47_dev_extension_js/proton.project.json
```

Run these commands from the repository root. The CLI reads the example's
`proton.project.json`, uses `frontend.before_dev` to start Warren from
the configured `frontend.path`, then
overrides the code-declared asset entry with `frontend.dev_url` in development.
Warren compiles `frontend/main` to JavaScript and serves `frontend/public` at
`http://127.0.0.1:4300`. The page receives `window.__MoonBit__.ticker` from native
bridge injection; it does not load a Proton script manually.

For a production build:

```powershell
proton_cli -C . build --config examples/47_dev_extension_js/proton.project.json
```

`proton_cli build` runs `frontend.before_build`, validates
`frontend/dist/index.html`, then builds the native MoonBit app. In production
the app loads Warren's output through Proton's `proton://` asset route.

Run the development and production E2E probes with:

```sh
moon -C e2e run test --target native -- --dev-extension
```
