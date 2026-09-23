# Diagnostics reference

Diagnostics come from distinct layers: project/toolchain validation, native startup and lifecycle, bridge requests, and frontend rendering. A successful frontend preview does not verify native operations; a successful build does not verify packaged execution.

## Diagnostic interfaces

| Interface | Scope |
| --- | --- |
| `proton_cli doctor` | Read-only project, toolchain, runtime and helper checks |
| `proton_cli --version` / `moon version` | Tool versions |
| `BrowserHandle.open_devtools()` | Chromium inspector for a browser |
| `App.run()` | Typed application execution errors |
| `App.run_or_abort()` | Error reporting followed by abort on failure |
| `ClientFailure` | Frontend contract, bridge, transport and decoding failures |

`WindowHandle.browser()` provides the browser handle. DevTools belongs to that browser's lifetime. Opening it from a window-ready hook must preserve any existing hook state and cleanup behavior.

## Logs

Proton uses `tonyfettes/xlog`. Development output uses stderr; packaged applications use the platform log directory. Application categories use `app.*`; framework categories use `proton.*`. Application level and category settings are preserved.

| Environment variable | Effect |
| --- | --- |
| `MOON_XLOG` | xlog filtering |
| `PROTON_LOG_OUTPUT=stderr` | Select stderr output, including for terminal-launched packaged apps |
| `PROTON_CEF_LOG` | Temporary switch for separate CEF internal diagnostics; disabled by default |

File output depends on packaged metadata. CEF diagnostics are not the application logging interface.

## Failure classification

| Symptom | Relevant boundary |
| --- | --- |
| Missing runtime/helper | Setup-managed release and platform selection |
| Frontend command not found | Installed tool and PATH; Warren is installed separately |
| Bridge unavailable | Page is outside the Proton renderer environment |
| Unknown operation | Missing command binding or capability |
| Decode failure | Request/response type and serialized payload mismatch |
| Window gone but process remains | Lifecycle policy, active child browsers and cleanup completion |
| Packaged page missing assets | Asset paths, frontend output and resource assembly |

A useful report includes the exact command, full error, Proton/MoonBit versions, OS and architecture, development versus packaged mode, and the smallest reproduction. Process termination must be distinguished from normal shutdown completion.
