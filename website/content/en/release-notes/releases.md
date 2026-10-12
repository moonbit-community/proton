# Release Notes

## 0.4.0 (Unreleased)

0.4.0 unifies window and browser APIs, shares typed configuration between the application and CLI, and coordinates update installation with application shutdown. This release includes breaking API changes.

**Breaking API changes and migration**

| Area | 0.3.4 | 0.4.0 |
| --- | --- | --- |
| Window configuration | Separate primary-window setters and `add_window(id, title, entry, ...)` | `WindowConfig` shared by `App(config)`, `main_window(config)` and `add_window(id, config, ...)` |
| Initial child views | `App.with_view(...)` | `WindowConfig.views`, for primary or secondary windows |
| Browser operations | `window.browser()` and page methods directly on `ViewHandle` | `window.web_contents()` and `view.web_contents()`, both returning `WebContentsHandle` |
| Browser events | `BrowserEvent`, `ViewEvent`, separate subscriptions | `WebContentsEvent` and `on_web_contents_event`; use `window_id()` and optional `view_id()` for identity |
| Sessions | Browser-owned handle, `SessionHandle.window_id()`, `WindowSessionError` | Application-owned handle, `context.session()`, `SessionError`; no `window_id()` |
| PDF | Request number plus `PdfPrinted` / `PdfPrintResult` | Async `web_contents.print_to_pdf(path, options?) -> Unit` |
| Configuration | `app.load_config()`, `ProjectConfig`, `AppMetadataError` | `app.config(@proton.load_config())`, typed `AppConfig`, `AppConfigError` |
| Updates | `update.install(); update.restart()` | `update.download(); context.quit_and_install()` |

- **Window configuration:** move `title`, `size`, `theme`, `titlebar_style`, `traffic_light_position`, and `entry_*` builder settings into `WindowConfig`. `html`, `url`, `file`, and `asset` remain shortcuts; live native-window controls remain on `WindowHandle`. Window registration copies the initial views array, and secondary-window reopening recreates declared children. [#417](https://github.com/moonbit-community/proton/pull/417)
- **Web contents:** `WebContentsHandle` becomes an opaque common handle rather than an enum to unpack. Navigation, download, and permission callbacks receive it too. Move window zoom and child-page operations to this handle; layout, visibility, z-order and removal stay on the view. Child pages gain printing, downloads and session access, but do not gain the application command bridge. Request completions remain associated with the originating page, and macOS main-page title updates are delivered correctly. [#418](https://github.com/moonbit-community/proton/pull/418)
- **Session lifetime:** cookies, cache, authentication, certificate exceptions and connection operations use the shared application request context. Handles work before windows open and after pages close, including `KeepRunning` with no windows. Concurrent cookie reads are independent; runtime teardown wakes pending readers and invalidates retained handles. Update exception handling to `SessionError`. This remains one shared profile, not per-window sessions. [#419](https://github.com/moonbit-community/proton/pull/419)
- **PDF completion:** call `print_to_pdf` in an async context and handle completion directly; remove request/event correlation. Page closure, renderer termination and application shutdown end outstanding waits. Cancellation stops waiting, not the native print job, so a file may still be produced. [#433](https://github.com/moonbit-community/proton/pull/433)
- **Typed configuration:** `@proton.load_config()` reads the complete configuration once; fields such as `config.frontend.dev_url` remain directly accessible. `App.config(config)` keeps an independent snapshot, and `name()` / `version()` read it without reopening files. CLI development overrides are included in the launch snapshot. Packaged `proton-package.json` now has the complete configuration shape with nested `package`; rebuild application and packaged metadata together. Rabbita and scaffold defaults advance to 0.16.4, removing the deprecated moonback dependency. [#435](https://github.com/moonbit-community/proton/pull/435)
- **Update lifecycle:** downloading verifies and retains the artifact without replacing files. Installation follows cancelable quit and successful runtime cleanup. Denying quit retains the download; ordinary quit discards it; forced exit supersedes installation. A successful handoff terminates the old process even with exit code zero. `quit_and_install()` returns on request acceptance, not replacement startup. The extension response is now `UpdateDownloaded`, without the old `changed` field. [#436](https://github.com/moonbit-community/proton/pull/436)

**Fixes**

- Cancelling the task running `App.run()` now cleans up native windows, browsers and helpers during both startup and normal execution. Cancellation still propagates to the caller. [#414](https://github.com/moonbit-community/proton/pull/414)
- Linux and macOS packaging correctly copies files and directories whose paths begin with `-`, preserving executable permissions. [#415](https://github.com/moonbit-community/proton/pull/415)
- Update installation retains single-instance ownership while replacing application files. Automatic Windows updates wait for the original process to exit instead of forcibly terminating it. macOS relaunch works when the new version changes its executable name. macOS/Linux applications with an update channel reject delayed starts of the replaced executable. [#436](https://github.com/moonbit-community/proton/pull/436)

**Upgrading**

Keep the CLI and application `proton_*` dependencies on the same version, then run `proton_cli cef setup` for the matching helper. Installing the new CLI does not migrate existing application code. Rebuild packaged applications to generate the new configuration format.

Rabbita is updated to 0.16.4. Warren remains 0.3.3 and async remains 0.22.4; the CEF version is unchanged. See [application APIs](../introduction/application-api.md), [configuration](../configuration/project.md) and the [complete changelog](https://github.com/moonbit-community/proton/compare/51a88c4c0892ff9628e5795fc598d05262e96daa...bdb169302952db553deda6de015887c7a6a19831).

## 0.3.4 — 2026-09-28

- **Lifecycle:** application quit interception and forced exit, application-level window/browser/session events, and focus/visibility controls. Fixes cover forced exit during `will_quit`, `exit(0)`, child-renderer termination, page recovery, and closed-window collection.
- **Communication:** preserve command error codes, separate command failures from runtime failures, and remove the global pending-request limit. Extension operation inventories now come from bindings.
- **Browser APIs:** navigation history and inserted CSS controls; task metrics distinguish CEF tasks from processes.
- **Platforms and packaging:** Windows desktop media consent and child-view geometry fixes; macOS query autorelease pools and alert layout; recoverable packaging locks, explicit minimum macOS version metadata, and executable Linux helpers in AppImage staging.
- **CLI:** explicit `new` options no longer prompt again. Async is updated to 0.22.4.

**Upgrade notes**

Keep the CLI and application `proton_*` modules on 0.3.4 and run `proton_cli cef setup` for the matching helper. Reinstalling the CLI does not rewrite existing projects.

The briefly introduced `app_metrics` API is now `task_metrics` with `AppTaskMetric`: task identity is not process identity, and `process_cpu_percent` / `process_memory_bytes` can repeat across tasks. Do not sum task rows as application resource usage. See [PR #412](https://github.com/moonbit-community/proton/pull/412). Unused legacy command configuration APIs were removed in [PR #408](https://github.com/moonbit-community/proton/pull/408); application command bindings remain the supported route.

## 0.3.3 — 2026-09-21

- **View lifecycle:** removed and explicitly closed child views retain the identity needed to deliver their terminal close event. Coverage includes views closed before browser creation and stale events after replacement. [PR #378](https://github.com/moonbit-community/proton/pull/378)
- **Dependencies:** async 0.22.1, x 0.5.5, lexer/parser/moon_config 0.4.0, Rabbita 0.16.2 and Warren 0.3.3. Scaffold defaults and documentation now use these versions. Cancellation handling and protected cleanup follow async's new semantics. [PR #379](https://github.com/moonbit-community/proton/pull/379)

**Updating an application**

Use 0.3.3 consistently for the application's `proton_*` dependencies and CLI. Existing projects retain their configuration and source; installing a new CLI does not rewrite them. Install Warren 0.3.3 when using the isomorphic frontend, and run `proton_cli cef setup` for the matching helper before building.

Applications that directly use async should review its 0.22 cancellation behavior: cancellation is no longer caught as an ordinary error. A cancelled task's `wait()` can report `TaskCancelled`; child process shutdown can complete with an exit result after reaping.

**Earlier releases**

[0.3.2 changes](https://github.com/moonbit-community/proton/pull/377) and [repository history](https://github.com/moonbit-community/proton/commits/main/) contain earlier changes.
