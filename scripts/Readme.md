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

## `install_webview2_headers.ps1`

Downloads the Microsoft WebView2 SDK NuGet package and installs its native
headers into the CMake-compatible layout expected by Windows native stubs:

```text
build/_deps/microsoft_web_webview2-src/build/native/include
```

This only installs SDK headers. Windows users still need the WebView2 Runtime
installed to run WebView2-based applications.

### Usage

Install the default SDK version used by CI:

```powershell
.\scripts\install_webview2_headers.ps1
```

Install a specific SDK version:

```powershell
.\scripts\install_webview2_headers.ps1 -Version 1.0.3967.48
```

The generated `build/` directory is ignored by git.

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

Starts the multi-process examples with WebView2 remote debugging enabled,
connects through CDP, and verifies that JavaScript calls can cross the
user-process/framework-process boundary.

This script requires Windows, WebView2 Runtime, WebView2 SDK headers, and
Node.js 24 or newer.

### Usage

```sh
node ./scripts/e2e_cdp_smoke.mjs
```

By default it runs examples `38` through `41`. Pass one or more scenario names
to run a subset:

```sh
node ./scripts/e2e_cdp_smoke.mjs 41_app_commands/app
```

Run startup smoke coverage for every runnable example:

```sh
node ./scripts/e2e_cdp_smoke.mjs --all-examples
```
