# Examples

Run a specific example with:

```sh
moon -C examples run 19_app_fs --target native
```

Build every runnable example with:

```sh
moon -C examples build --target native
```

Run the Windows CEF examples by building the MoonBit subprocess helper first,
then passing that helper path to the app build:

```powershell
$env:LEPUS_CEF_ROOT = "C:\path\to\cef_binary_..._windows64_minimal"
Remove-Item Env:\LEPUS_CEF_SUBPROCESS_PATH -ErrorAction SilentlyContinue
moon build src\cef_process --target native
$env:LEPUS_CEF_SUBPROCESS_PATH = (Resolve-Path "_build\native\debug\build\justjavac\lepus\cef_process\cef_process.exe").Path
moon -C examples run 43_cef_bind_smoke --target native
moon -C examples run 37_cef_mvp --target native
```

Run the Windows CEF e2e smoke scenarios with both CEF environment variables set:

```powershell
node ..\scripts\e2e_cdp_smoke.mjs
```

## Core Webview

| Name            | Status | Note |
| --------------- | ------ | ---- |
| 01_run          | OK     | Basic window creation |
| 01_tauri_like_helloworld | OK | Tauri-style hello world with `webview.bind(...)` |
| 02_local        | OK     | Loading local HTML files |
| 03_remote       | OK     | Loading remote web pages |
| 04_user_agent   | OK     | Custom user agent configuration |
| 05_alert        | Partial | Works on Windows, no response on macOS |
| 06_onload       | OK     | Handling page load events |
| 07_inject_js    | OK     | Injecting JavaScript code |
| 08_eval         | OK     | Evaluating JavaScript expressions |
| 09_dispatch     | OK     | Dispatching work onto the UI thread |
| 10_bind         | OK     | Binding __MoonBit__ functions to JavaScript |
| 11_multi_window | OK     | Multiple window management |
| 12_embed        | OK     | Embedding resources |
| 13_todo         | OK     | Complete todo application |
| 14_beforeunload | OK     | Preventing unload with the browser `beforeunload` event |
| 15_close        | OK     | Closing the webview from page JavaScript |

## Runtime And App

| Name           | Status | Note |
| -------------- | ------ | ---- |
| 17_extension | OK | Custom extension mounted on `window.__MoonBit__` |
| 18_extension_fs | OK | Filesystem workbench using `@fs.extension()` and `window.__MoonBit__.fs` |
| 19_app_fs | OK | `justjavac/lepus_app` startup with `fs` and `path` |
| 20_app_desktop | OK | App startup with `dialog` and `clipboard` |
| 21_app_shell | OK | App startup with the `shell` extension |
| 22_app_config | OK | Declarative startup through `@app.create_app_from_file("app.json", ...)` |
| 23_ops_runtime | OK | Direct `window.__MoonBit__.core.invokeOp(...)` plus extension proxies |
| 24_app_multi_window | OK | Multi-window startup with main and secondary windows |
| 25_app_system | Windows-only | Notification, tray, and global hotkey in one runtime |
| 26_app_path | OK | Focused `path` extension example using `window.__MoonBit__.path` |
| 27_app_notification | Windows-only | Focused notification extension example |
| 28_app_tray | Windows-only | Focused tray extension example |
| 29_app_global_hotkey | Windows-only | Focused `globalHotkey` extension example |
| 30_app_asset_origin | WebView2-only | `AppEntry::Asset(...)` through a secure in-process origin with `SharedArrayBuffer` probing; unsupported under root CEF |
| 31_app_asset_bundle | WebView2-only | Asset bundle demo with separate `index.html`, `app.js`, and `styles.css`; unsupported under root CEF |
| 32_shared_buffer_benchmark | WebView2-only | Prototype benchmark comparing JSON bridge payloads with WebView2 shared buffers; unsupported under root CEF |
| 33_app_auto_launch | Platform-dependent | Focused `autoLaunch` extension example |
| 34_app_keepawake | Platform-dependent | Focused `keepAwake` extension example |
| 35_app_microphone | Platform-dependent | Focused `microphone` extension example |
| 36_app_devtools | WebView2-only | Focused `devtools` extension example; unsupported under root CEF |
| 37_cef_mvp | Windows CEF MVP | Root `justjavac/lepus` backend rendered through CEF |
| 38_async_extension_add | OK | Async extension API implemented by a user process that starts a framework child |
| 39_sync_async_extensions | OK | Sync and async command extensions registered through the same manifest/registry style |
| 40_event_broadcast | OK | Ticker extension implemented in the user process with a framework child |
| 41_app_commands | OK | App-level commands implemented in the user process with a framework child |
| 42_attribute_codegen_commands | OK | App command extension generated from `#lepus.command` and `#lepus.event` attributes |
| 43_cef_bind_smoke | Windows CEF smoke | Automated `webview.bind(...)` / `webview.response(...)` Promise marshalling smoke |

## Notes

- Examples `17` and `18` show direct low-level installation with `@core.install_extension(...)`.
- Examples `19` through `36` show app-style startup with `justjavac/lepus_app`.
- Example `38` shows async extension-style APIs with the user process starting a framework child process.
- Example `39` shows sync and async extension-style APIs registered through one command extension registry.
- Example `40` keeps the WebView responsive while ticker work runs in the user command-host process.
- Example `41` demonstrates the multiprocess runtime split: MoonBit ops and
  async handlers stay in the user parent process while browser runtime work
  runs in a framework child process.
- Example `42` shows the generated-command workflow. Regenerate its command
  bridge by first installing the CLI with
  `moon install ./cli --bin target/lepus-tools`. The package pre-build then
  calls `target/lepus-tools/lepus_cli codegen`; extension id and namespace come
  from `42_attribute_codegen_commands/extension.json`.
- Example `43` exits on its own after JavaScript calls a MoonBit binding,
  receives a response, and reports the Promise result back through a second
  binding.
- App examples declare extensions in MoonBit code and keep per-extension options in `app.json.extensions`.
- Frontend code should use `window.__MoonBit__` throughout.
