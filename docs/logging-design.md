# Proton Logging Design

Status: accepted design; implementation has not started.

## Decision

Proton uses `tonyfettes/xlog` 0.4.1 as its logging API and implementation model.
It does not define parallel `LogLevel`, `LoggingConfig`, `Logger`, record,
filter, or handler abstractions.

Proton owns only the desktop-runtime integration that a general logging library
cannot provide:

- selecting the default handler for development and packaged applications;
- resolving the application-specific platform log path;
- opening and closing that handler with the application runtime;
- translating selected framework diagnostics into `proton.*` xlog events.

Logging is observability only. It never participates in control flow and never
replaces typed errors, lifecycle events, startup failure UI, exit status, or
platform crash reports.

## xlog Model

Applications use xlog directly. Both its process-global logger and explicitly
constructed logger instances remain available:

```moonbit
@xlog.info(category="app.sync") <? {
  "message": "synchronization started",
  "account": account_id,
}
```

Proton follows the xlog 0.4.1 model:

- levels are `Fatal`, `Error`, `Warn`, `Info`, `Debug`, and `Trace`;
- categories are hierarchical and use longest-prefix configuration matching;
- fields are structured `Json` values written through conditional events;
- source locations are captured by xlog;
- logger calls are best-effort and do not propagate handler failures;
- configuration and handlers may be replaced through xlog's existing mutable
  logger API;
- `MOON_XLOG` is the level and category-filter environment variable.

Proton does not wrap these types or expose another logger through
`ApplicationContext` or `WindowContext`. Application and framework records share
the same xlog root logger unless an application deliberately constructs an
independent logger.

Application categories should use `app.*`. Proton framework categories use the
reserved `proton.*` prefix. This is a documented naming convention rather than
a second validation layer over xlog.

## Ownership And Native Boundary

The MoonBit runtime configures xlog and emits all Proton records. There is no
generic logging ABI in the native engine.

Native C, Objective-C, and C++ code reports facts through the existing
boundaries:

- synchronous failures return a status and diagnostic detail;
- asynchronous failures enqueue typed native events;
- lifecycle changes enqueue their existing typed events.

The MoonBit runtime may convert those results into xlog events. Native callbacks
never enter MoonBit, and native engine code never opens or writes Proton log
files.

CEF diagnostics remain separate and may be enabled temporarily through
`PROTON_CEF_LOG`. Fatal native crashes are diagnosed through platform crash
facilities, not through xlog.

Other repository components keep their ownership boundaries:

- `proton_cli`, `proton_package`, and `proton_cefsetup` render command-line UI;
- standalone `sys` modules return typed errors and do not depend on Proton's
  configured root logger;
- renderer `console` output remains in Chromium DevTools and is not forwarded
  through the bridge;
- `proton/core` accepts a diagnostic reporter from the facade and does not
  print directly.

## Application Identity

Every application has an explicit identifier configured independently from
single-instance behavior:

```moonbit
@proton.html(page)
.identifier("com.example.app")
.single_instance()
```

The identifier is required and supplies the stable identity used by platform
log paths and other operating-system integration. `single_instance()` only
enables the single-instance policy; it does not accept or define identity.

## Startup Configuration

At startup Proton selects an initial handler and xlog configuration. The
application may subsequently use xlog's normal APIs to replace either.

Ordinary launches start with `Warn` written to the platform log file.
`proton_cli dev` explicitly launches the child process with `Info` and
standard-error output. Logging does not infer its behavior from `PROTON_MODE`.

`MOON_XLOG` keeps xlog's native syntax for root levels and hierarchical category
overrides, for example:

```text
warn,proton.bridge=debug,app.sync=trace
```

`PROTON_LOG_OUTPUT` is limited to Proton's initial desktop handler selection:
`stderr` or `file`. It does not encode a path or duplicate xlog's filtering
configuration. `proton_cli dev` sets it explicitly to `stderr` for the child
process.

The root logger and handler exist before Proton creates the native runtime and
remain alive until application cleanup, window teardown, and native runtime
destruction have completed.

## Handlers And Files

Proton adds two private implementations of xlog's open `Handler` trait:

- a standard-error handler that writes through MoonBit's stderr API;
- a platform file handler that owns path resolution and file lifetime.

There is no composite handler, background logging task, queue, rolling policy,
upload service, or in-application log viewer in Proton. Applications remain free
to use other xlog handlers directly.

The platform file handler writes synchronous UTF-8 text under the
application's user log location:

- macOS: `~/Library/Logs/<identifier>/`;
- Windows: `%LOCALAPPDATA%\<identifier>\Logs\`;
- Linux: `$XDG_STATE_HOME/<identifier>/logs/`.

Per-process filenames prevent concurrent instances from truncating each
other's output. Proton does not use xlog 0.4.1's built-in `File` handler on
Windows because it passes a UTF-8 MoonBit path to `fopen`; Proton's handler must
use the repository's Unicode-safe Windows path boundary. The same Proton
handler contract is used across platforms.

Opening the selected file is part of startup and may raise a typed startup
error. Once logging is active, handler writes follow xlog semantics: failures
are best-effort and do not alter application control flow.

## Framework Record Policy

Framework logging is limited to low-frequency boundaries: runtime startup and
shutdown, window creation and closure, bridge startup results, extension
registration failures, and non-recoverable native diagnostics.

Bridge failures may include the command name, stable error code, and duration.
They do not include request or response payloads. Proton does not log headers,
cookies, tokens, clipboard contents, file contents, or complete local paths and
URLs. Detailed native diagnostics are never sent to the renderer.

## Testing

Pure tests cover Proton's handler selection, platform path resolution, and
framework-to-xlog event mapping. xlog remains responsible for testing levels,
category filtering, event construction, formatting, and its public API.

Integration tests may verify that a selected destination receives records.
Logs are not a behavioral contract. E2E tests must observe typed errors, events,
browser targets, process state, and filesystem results directly; they must not
search log text as proof of lifecycle behavior.
