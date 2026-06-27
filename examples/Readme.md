# Examples

Run commands from the repository root.

Install or assemble the native runtime first:

```powershell
moon -C cli run . -- -C .. cef setup
$runtime = (Get-Content .proton\runtime.json | ConvertFrom-Json).dist
$env:PATH = (Resolve-Path "$runtime\bin").Path + ';' + $env:PATH
```

Generated-command examples use the released Proton CLI. Install it into the
tool directory used by `examples/moon.mod`:

```sh
moon install justjavac/proton_cli --bin target/proton-tools
```

The installed executable is `proton_cli`; this repository's build rules call the
CLI through `moon -C ../cli run ...` during local development.

Build the minimal root-facade example:

```sh
moon -C examples build 01_run --target native
```

Run one example:

```sh
moon -C examples run 01_run --target native
```

## Groups

- `01_run`: minimal app-style startup through `justjavac/proton`
- `02_*` through `18_*`: root-facade examples that compile against the native
  DLL route
- `19_*` through `35_*`: extension and app-capability examples for filesystem,
  path, shell, desktop integration, notification, tray, hotkey, auto-launch,
  keepawake, and microphone behavior.
- `41_app_commands`: current `core.invokeOp` bridge smoke for the native DLL
  route.
- `38_*` and `39_*`: inline HTML command-extension proxy examples backed by the
  native DLL bridge.
- `40_event_broadcast`: command-extension event broadcast over the native DLL
  bridge.
- `42_attribute_codegen_commands`: generated command metadata plus generated
  event helper over the native DLL bridge.
- `44_project_config`: `moon.proton` project config decoding

All runnable examples should import `justjavac/proton`. `moon.proton`
configures app settings such as window, entry, debug, frontend, and bundle
metadata.
