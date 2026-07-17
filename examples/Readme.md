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

To create a fresh app project instead of working inside `examples/`, use:

```sh
proton_cli new my-counter
```

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
- `25_app_system`: combined notification, tray, and global-hotkey runtime with
  tray support reporting and menu items that trigger visible app actions.
- `28_app_tray`: focused tray support reporting, lifecycle, tooltip/icon update,
  flat menu, menu-item events, and platform-specific tray-icon click events.
- `37_native_mvp`: direct native-window MVP smoke for the native DLL route.
- `38_*` and `39_*`: inline HTML command-extension proxy examples backed by the
  native DLL bridge.
- `40_event_broadcast`: command-extension event broadcast over the native DLL
  bridge.
- `41_app_commands`: current `core.invokeOp` bridge smoke for the native DLL
  route.
- `42_attribute_codegen_commands`: generated command metadata plus generated
  event helper over the native DLL bridge.
- `43_native_bind_smoke`: low-level native binding smoke.
- `44_project_config`: `moon.proton` project config decoding
- `45_bridge_multi_window`: multi-window bridge smoke.
- `46_asset_sidecar_resources`: `@proton.asset` HTML with sibling JS/CSS files.
- `47_child_process_close_repro`: minimal bridge request with a long-lived child
  process for macOS close-lifecycle debugging.
- `48_app_menu`: native app menu API with macOS menu command events.
- `47_dev_extension_js`: Vite dev-server injection smoke for extension
  JavaScript helpers and events.

All runnable examples should import `justjavac/proton`. `moon.proton`
configures app settings such as window, entry, debug, frontend, and bundle
metadata.

Tray v1 is implemented by the `tray` extension through `justjavac/tray`; Proton
native C does not expose a tray ABI. Windows is the baseline for tray-icon
click/right-click/double-click events. Menu item clicks are the portable event
path across Windows, Linux, and macOS when the desktop backend supports menu
activation. Linux needs GTK 3 plus AppIndicator or Ayatana AppIndicator in the
desktop session.
