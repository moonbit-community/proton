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

## `sync_libwebview.mjs`

Refreshes the vendored native libraries under [`lib/`](../lib) from a GitHub
Actions run in [`justjavac/libwebview`](https://github.com/justjavac/libwebview).

### Requirements

- Node.js
- GitHub CLI (`gh`)
- access to download workflow artifacts from the target repository

### Usage

Use the latest successful `build` workflow run:

```sh
node ./scripts/sync_libwebview.mjs
```

Use a specific workflow run:

```sh
node ./scripts/sync_libwebview.mjs --run-id 123456789
```

Use a different repository:

```sh
node ./scripts/sync_libwebview.mjs --repo owner/name
```

### What It Updates

- `lib/windows-x64/webview.lib`
- `lib/windows-x64/BUILD_INFO.txt`
- `lib/macos-universal/libwebview.a`
- `lib/macos-universal/BUILD_INFO.txt`
- `lib/linux-x64/libwebview.a`
- `lib/linux-x64/BUILD_INFO.txt`

Downloaded artifacts are staged through `target/libwebview-sync/` and removed before each sync.

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
