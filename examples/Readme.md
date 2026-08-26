# Examples

Run commands from the repository root.

Install or assemble the native runtime first:

```powershell
$runtime = moon -C cefsetup run . --target native | Select-Object -Last 1
$env:PATH = (Resolve-Path "$runtime\bin").Path + ';' + $env:PATH
```

```sh
runtime="$(moon -C cefsetup run . --target native | tail -n 1)"
export PATH="$runtime/bin:$PATH"
```

Generated-command examples build and run the repository's standalone
`proton_codegen` WASM executable through Moon prebuild rules. Released
applications use the same executable through `moonx`.

To create a fresh app project instead of working inside `examples/`, install
the released CLI and scaffold a project:

```sh
moon install moonbit-community/proton_cli
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

- `01_run`: minimal app-style startup through `moonbit-community/proton`
- `02_local`, `03_remote`, and `12_embed`: root-facade entry variants.
- `18_extension_fs`: command-extension filesystem integration.
- `19_*` through `35_*`: extension and app-capability examples for filesystem,
  path, shell, desktop integration, notification, tray, hotkey, auto-launch,
  keepawake, and microphone behavior.
- `22_app_builder`: window, file entry, size, and debug behavior declared with
  the MoonBit App builder.
- `25_app_system`: combined notification, tray, and global-hotkey runtime with
  tray support reporting and menu items that trigger visible app actions.
- `28_app_tray`: focused tray support reporting, lifecycle, tooltip/icon update,
  flat menu, menu-item events, and platform-specific tray-icon click events.
- `37_native_mvp`: direct native-window MVP smoke for the source-built runtime.
- `38_*` and `39_*`: inline HTML command-extension proxy examples backed by the
  source-built native bridge.
- `40_event_broadcast`: command-extension event broadcast over the source-built native
  bridge.
- `41_app_commands`: current `core.invokeOp` bridge example and E2E fixture for the source-built native
  route.
- `app_commands_fixture`: non-runnable shared implementation used by
  `41_app_commands` and the MoonBit E2E suite.
- `e2e_fixtures`: non-runnable shared scenario implementations used by the
  MoonBit E2E suite (`e2e/`).
- `42_attribute_codegen_commands`: generated command metadata plus generated
  event helper over the source-built native bridge.
- `44_app_activation`: single-instance URL and document activation configured
  through the App builder.
- `45_bridge_multi_window`: typed facade multi-window bridge E2E example.
- `46_asset_sidecar_resources`: `@proton.asset` HTML with sibling JS/CSS files.
- `47_dev_extension_js`: Vite dev-server injection smoke for extension
  JavaScript helpers and events.
- `48_titlebar_overlay`: cross-platform overlay demo with native window
  controls and compact web-rendered application chrome.
- `49_app_menu`: app-level typed native menu roles and menu command events with
  the optional focused window id.
- `50_browser_control`: asynchronous navigation, popup, download, certificate,
  media-permission, and download-progress browser policy handlers.
- `51_child_process_close_repro`: long-lived child process and pending bridge
  request for macOS close-lifecycle regression testing.
- `52_web_contents_view`: Codex-style built-in browser: an asset-loaded
  sidebar host page drives an embedded web contents view through a command
  extension, with view events keeping the sidebar in sync.
- `53_view_minimal`: the minimal declarative web contents view example:
  `with_view` plus `@proton.view`, no lifecycle hooks required.
- `54_devtools`: opens CEF DevTools programmatically through
  `BrowserHandle::open_devtools` and closes it with the window lifecycle.
- `55_desktop_showcase`: presentation-ready macOS desktop capability console
  combining native dialogs, clipboard access, notifications, and tray menus.
- `56_i18n`: one explicit application locale observed through MoonBit command
  context, CEF `navigator.languages`, and localized typed native menus.
- `57_background_residency`: keeps the process alive after the last window
  closes, then recreates the main window when a second launch delivers
  `Reopen`; this is the lifecycle used by messaging and synchronization apps.
- `58_context_menu`: manual Electron-style window context menu review with
  native macOS, Windows, and Linux popups at renderer CSS-pixel coordinates,
  nested submenu items, role items, and menu command events.
- `59_window_progress`: manual Electron-style window progress review with
  determinate, indeterminate, cleared, and animated macOS Dock states.
- `60_window_attention`: manual Electron-style window attention review with
  macOS Dock bouncing, Windows taskbar flashing, Linux urgency hints,
  activation cancellation, and timed explicit cancellation.
- `61_window_resizable`: manual Electron-style live window resizing review with
  enable, disable, toggle, and cross-platform native frame checks.
- `62_window_size_limits`: manual Electron-style minimum and maximum window
  size review with live constraint updates and clear operations.
- `63_window_center`: manual Electron-style window centering review using the
  current monitor work area and native frame size.
- `64_window_movable`: manual Electron-style window movement control with
  native drag blocking on macOS and Windows, Linux no-op behavior, and
  programmatic movement checks.
- `65_window_opacity`: manual Electron-style whole-window opacity review with
  a numeric slider, presets, and native frame checks.
- `66_window_skip_taskbar`: manual Electron-style taskbar visibility review
  with Windows taskbar tab removal and macOS/Linux no-op checks.

All runnable examples should import `moonbit-community/proton`. Runtime behavior
is configured through the App builder; `proton.project.json` is present only
when an example needs CLI frontend/build or package metadata.

Tray v1 is implemented by the `tray` extension through `moonbit-community/proton_tray`; Proton
native C does not expose a tray ABI. Windows is the baseline for tray-icon
click/right-click/double-click events. Menu item clicks are the portable event
path across Windows, Linux, and macOS when the desktop backend supports menu
activation. Linux needs GTK 3 plus AppIndicator or Ayatana AppIndicator in the
desktop session.
