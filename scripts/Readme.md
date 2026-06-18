# Scripts

This directory holds small repository maintenance scripts.

## `embed_asset.mjs`

Embeds a text asset into a generated MoonBit source file as a multiline
`String`. It is used by `moon.pkg` pre-build steps in `core/` and built-in
extensions.

### Usage

```sh
node ./scripts/embed_asset.mjs <input> <output> <identifier>
```

The identifier must be a lower-snake-case MoonBit binding name. The script
creates the output directory when needed.

## `setup_cef.mjs`

Downloads and extracts the Windows CEF binary distribution used by the root CEF
backend. The script validates the expected CEF layout and prints the extracted
CEF root path.

### Usage

Download the default CEF build into `.cef-cache/`:

```powershell
node .\scripts\setup_cef.mjs
```

Use a different cache directory:

```powershell
node .\scripts\setup_cef.mjs --cache D:\Code\moonbit-webview\.cef-cache
```

After downloading, set `LEPUS_CEF_ROOT` explicitly before building CEF-backed
native targets:

```powershell
$env:LEPUS_CEF_ROOT = (Resolve-Path ".\.cef-cache\cef_binary_147.0.14+g76d2442+chromium-147.0.7727.138_windows64_minimal").Path
```

## `e2e_cdp_smoke.mjs`

Starts CEF examples with remote debugging enabled, then runs the MoonBit
`e2e/test` probe built on `justjavac/cdp`. Examples that exit on
their own, such as `09_dispatch` and `43_cef_bind_smoke`, are checked directly
by the launcher.

The script uses `LEPUS_CEF_ROOT` when it is already set. Otherwise it looks for
an extracted Windows CEF build under `.cef-cache/`. It builds
`src/cef_process` automatically and sets `LEPUS_CEF_SUBPROCESS_PATH` for the
launched examples.

### Usage

Run all automated smoke scenarios:

```powershell
node .\scripts\e2e_cdp_smoke.mjs
```

Run a subset:

```powershell
node .\scripts\e2e_cdp_smoke.mjs 38_async_extension_add 41_app_commands
```
