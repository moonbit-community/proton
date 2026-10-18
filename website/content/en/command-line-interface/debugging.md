# Diagnostics reference

Diagnostics come from distinct layers: project/toolchain validation, native startup and lifecycle, bridge requests, and frontend rendering. A successful frontend preview does not verify native operations; a successful build does not verify packaged execution.

## Diagnostic interfaces

| Interface | Scope |
| --- | --- |
| `proton_cli doctor` | Read-only project, toolchain, runtime and helper checks |
| `proton_cli --version` / `moon version` | Tool versions |
| `WebContentsHandle.open_devtools()` | Chromium inspector for a browser |
| `App.run()` | Typed application execution errors |
| `App.run_or_abort()` | Error reporting followed by abort on failure |
| `ClientFailure` | Frontend contract, bridge, transport and decoding failures |

`WindowHandle.web_contents()` provides the browser handle. DevTools belongs to that browser's lifetime. Open it from `setup_window`; register any additional cleanup with that context's `add_cleanup`.

## CDP endpoint discovery

Set `PROTON_REMOTE_DEBUGGING_PORT=0` when launching the native application to let Chromium select an available port. Read the actual browser WebSocket endpoint from its process output:

```text
DevTools listening on ws://127.0.0.1:<port>/devtools/browser/<id>
```

Use the announced endpoint for that process lifetime; do not reserve and release a port before launch or assume a fixed port. An explicit port remains supported. This is Chromium's diagnostic endpoint, not Proton's application command transport.

The application must have debugging enabled (`App.debug()`); the port variable
does not enable it. For native MoonBit automation, see the optional
[`proton_cdp` library](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/cdp/README.mbt.md).

## Native CDP automation

`moonbit-community/proton_cdp@0.5.0` is an optional native automation dependency. It connects to an already running Proton or Chromium application; connecting does not launch a Chrome window. Explicit browser launch helpers are separate operations. The CDP library has no dependency on the Proton application runtime.

An automation executable imports `moonbitlang/async`, `moonbit-community/proton_cdp/client` and `moonbit-community/proton_cdp/page`. Given an announced endpoint and the title of an existing page:

```moonbit
async fn read_title(endpoint : String, title : String) -> Json {
  @async.with_task_group(tasks => {
    let page = @page.Page::connect(
      tasks,
      @client.parse_cdp_target(endpoint),
      title~,
    )
    page.evaluate("document.title")
  })
}
```

`Page.connect` selects a page; `target_id`, `url`, and `title` can disambiguate multiple targets. Connections belong to the supplied task group; leaving its scope closes them without closing the target application. `Page.close()` closes the connection explicitly. Page navigation and reload replace the execution context: use the returned `Navigation.wait_for_context()` before evaluating the new document. `Page.evaluate` is a single execution, not an automatic retry of potentially stateful JavaScript. A new execution context does not establish DOM or Proton bridge readiness; use `Page.wait_until` with an application-specific, side-effect-free predicate and an application-owned timeout when those are required.

See the [versioned CDP guide](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/cdp/README.mbt.md) for browser launch, screenshots and schema compatibility. CDP is for diagnostics and external automation, not an alternative application command bridge.

## Logs

Proton uses `tonyfettes/xlog`. Development output uses stderr; packaged applications use the platform log directory. Application categories use `app.*`; framework categories use `proton.*`. Application level and category settings are preserved.

| Environment variable | Effect |
| --- | --- |
| `MOON_XLOG` | xlog filtering |
| `PROTON_LOG_OUTPUT=stderr` | Select stderr output, including for terminal-launched packaged apps |
| `PROTON_CEF_LOG` | Temporary switch for separate CEF internal diagnostics; disabled by default |

File output depends on packaged metadata. CEF diagnostics are not the application logging interface.

## Locate the actual log

Packaged applications write proton-&lt;pid&gt;.log by default. Directories use the application identifier, not its display name:

| Platform | Default directory |
| --- | --- |
| macOS | ~/Library/Logs/&lt;identifier&gt;/ |
| Windows | %LOCALAPPDATA%\&lt;identifier&gt;\Logs\ |
| Linux | $XDG_STATE_HOME/&lt;identifier&gt;/logs/, or ~/.local/state/&lt;identifier&gt;/logs/ when unset |

App.path(AppPathKind::Logs) returns the resolved path. Use that result when set_path or set_app_logs_path overrides the default. PROTON_LOG_OUTPUT=stderr redirects a terminal-launched packaged app to the terminal; unpackaged apps cannot use file mode.

## Diagnose by stage

| Symptom | Check and next action |
| --- | --- |
| CLI cannot find runtime | Compare proton_cli --version with the application's proton dependency; inspect cef requirements and run cef setup; retain the complete setup error |
| dev never reaches frontend readiness | Run before_dev inside frontend.path, check dev_url host/port; use --no-frontend for an existing service instead of starting a second one |
| No bridge in a normal browser | Launch the native application through proton_cli dev; browser previews have no host bridge |
| permission_denied / unknown_op | Check bound descriptors, capability targets and current window/page; adding a module dependency is insufficient |
| Frontend command not found | Check that the configured tool is installed and on PATH; Warren is installed separately from Proton CLI |
| Request or response decode failure | Compare the command descriptor types with the actual JSON payload; inspect ClientFailure and backend logs |
| Packaged resource 404 | Inspect the artifact resource tree and relative HTML URLs, frontend.dist and package.resources; retry without a development server |
| Process remains after window close | Check KeepRunning and denied quit decisions first, then final exit/cleanup errors; record process state and do not count manual killing as successful shutdown |
| appimage packaging fails | Check the PNG and appimagetool --version; distinguish icon validation from create AppImage tool failures |

## Reporting a problem

Include the command and full error, Proton and MoonBit versions, OS and architecture, and whether the failure occurs in development or in a packaged application. Attach `proton_cli doctor --json` output, the relevant application log, and a minimal reproduction. For shutdown failures, record whether the process exited on its own or was terminated manually. Review logs for application data or credentials before sharing them.
