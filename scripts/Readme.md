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

Downloads and installs the Windows CEF binary distribution used by the root CEF
backend. The script validates the expected CEF layout, installs the CEF files
directly into `.cef-cache/`, writes `.cef-cache/version.txt`, and prints the CEF
root path.

### Usage

Download the default CEF build into `.cef-cache/`:

```powershell
node .\scripts\setup_cef.mjs
```

Windows native builds look for CEF in `.cef-cache/` automatically. If CEF is
missing, the build fails with the setup command.

The script also mirrors early-startup resource files such as `icudtl.dat` and
`*.pak` into `Release/`. CEF loads those files from the `libcef.dll` directory
before normal settings are fully applied.

## `e2e_cdp_smoke.mjs`

Starts CEF examples with remote debugging enabled, then runs the MoonBit
`e2e/test` probe built on `justjavac/cdp`. Examples that exit on
their own, such as `09_dispatch` and `43_cef_bind_smoke`, are checked directly
by the launcher.

The script verifies that CEF is installed in `.cef-cache/` and builds
`src/cef_process` automatically before launching examples. The runtime locates
the helper through the build-time default path during repository development;
packaged apps should place `cef_process.exe` beside the app executable.

### Usage

Run all automated smoke scenarios:

```powershell
node .\scripts\e2e_cdp_smoke.mjs
```

Run a subset:

```powershell
node .\scripts\e2e_cdp_smoke.mjs 38_async_extension_add 41_app_commands
```
