# Scripts

Small repository scripts used by generation workflows.

## `embed_asset.mjs`

Embeds a text file into generated MoonBit source.

```sh
node ./scripts/embed_asset.mjs <input> <output> <identifier>
```

## `verify_generated.mjs`

Checks that release metadata is aligned and that committed generated MoonBit
files match their sources. It writes fresh outputs to a temp directory and
compares them against the repository.

```sh
node ./scripts/verify_generated.mjs
```

Run this before publishing `proton` or `proton_ext`, and after changing any of:

- extension `#proton.command` annotations or `moon.ext` metadata
- `extensions/fs/assets/*.js`
- `extensions/path/assets/*.js`

Published library packages consume committed generated files directly; do not
put `dev_build` or repository-relative codegen rules back into `proton` or
`proton_ext` package metadata.

## `verify_release_metadata.mjs`

Checks that `proton/prebuilt/*/manifest.json` and the `proton new` template
default version match `proton/moon.mod`.

```sh
node ./scripts/verify_release_metadata.mjs
```

## `e2e_bridge_smoke.mjs`

Runs native DLL bridge smoke scenarios through CEF remote debugging. Build and
assemble the active runtime first, then run:

```powershell
moon -C cli run . -- -C .. cef setup
$runtime = (Get-Content .proton\runtime.json | ConvertFrom-Json).dist
$env:PATH = (Resolve-Path "$runtime\bin").Path + ';' + $env:PATH
```

```sh
node ./scripts/e2e_bridge_smoke.mjs 38_async_extension_add 39_sync_async_extensions
node ./scripts/e2e_bridge_smoke.mjs 40_event_broadcast
node ./scripts/e2e_bridge_smoke.mjs 41_app_commands 42_attribute_codegen_commands 45_bridge_multi_window
node ./scripts/e2e_bridge_smoke.mjs 47_dev_extension_js
```

The `e2e/` MoonBit module is part of `moon.work`. The script checks that
workspace membership before running the MoonBit e2e probe.

## `macos_package_smoke.mjs`

Runs the development-mode macOS packaging regression with an explicit ad-hoc
identity. It builds and packages `47_dev_extension_js`, verifies every nested
signature plus the plist, entitlements, archive, and staging cleanup, then
extracts the zip to a temporary directory and confirms that the real CEF bundle
starts with three nested Helper.app processes.

Set up the darwin runtime and frontend dependencies first, then run:

```sh
moon -C cli run . -- -C .. cef setup
npm --prefix examples/47_dev_extension_js/frontend ci
node ./scripts/macos_package_smoke.mjs
```

This is a local development check. It does not replace Developer ID signing,
Apple notarization, or the final Gatekeeper assessment used for a release.
