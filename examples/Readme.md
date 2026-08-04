# Examples

Run commands from the repository root.

Install or assemble the native runtime first:

```powershell
moon -C cli run . -- -C .. cef setup
$runtime = (Get-Content .proton\runtime.json | ConvertFrom-Json).dist
$env:PATH = (Resolve-Path "$runtime\bin").Path + ';' + $env:PATH
```

```sh
moon -C cli run . -- -C .. cef setup
runtime="$PWD/$(node -p "JSON.parse(require('fs').readFileSync('.proton/runtime.json', 'utf8')).dist")"
export PATH="$runtime/bin:$PATH"
```

Generated-command examples run the repository CLI through
`moon -C ../cli run ... codegen` build rules; no separate CLI install is
needed when working inside this repository.

To create a fresh app project instead of working inside `examples/`, install
the released CLI and scaffold a project:

```sh
moon install justjavac/proton_cli
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
  DLL route (`02_local`, `03_remote`, `12_embed`, `17_extension`,
  `18_extension_fs`).
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
- `41_app_commands`: current `core.invokeOp` bridge example and E2E fixture for the native DLL
  route.
- `app_commands_fixture`: non-runnable shared implementation used by
  `41_app_commands` and the MoonBit E2E suite.
- `e2e_fixtures`: non-runnable shared scenario implementations used by the
  MoonBit E2E suite (`e2e/`).
- `42_attribute_codegen_commands`: generated command metadata plus generated
  event helper over the native DLL bridge.
- `44_project_config`: `moon.proton` project config decoding
- `45_bridge_multi_window`: typed facade multi-window bridge E2E example.
- `46_asset_sidecar_resources`: `@proton.asset` HTML with sibling JS/CSS files.
- `47_dev_extension_js`: Vite dev-server injection smoke for extension
  JavaScript helpers and events.
- `48_titlebar_overlay`: cross-platform overlay demo with native window
  controls and compact web-rendered application chrome.
- `49_app_menu`: app-level native menu definitions and macOS menu command
  events with the optional focused window id.
- `50_browser_control`: asynchronous navigation, popup, download, certificate,
  media-permission, and download-progress browser policy handlers.
- `51_child_process_close_repro`: long-lived child process and pending bridge
  request for macOS close-lifecycle regression testing.
- `52_web_contents_view`: Codex-style built-in browser: a sidebar host page
  drives an embedded web contents view through a command extension, with the
  view following window resizes.

All runnable examples should import `justjavac/proton`. `moon.proton`
configures app settings such as window, entry, debug, frontend, and bundle
metadata.

Tray v1 is implemented by the `tray` extension through `justjavac/tray`; Proton
native C does not expose a tray ABI. Windows is the baseline for tray-icon
click/right-click/double-click events. Menu item clicks are the portable event
path across Windows, Linux, and macOS when the desktop backend supports menu
activation. Linux needs GTK 3 plus AppIndicator or Ayatana AppIndicator in the
desktop session.
