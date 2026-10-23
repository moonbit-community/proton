# Release Notes

## Unreleased

**Linux auto-launch**

Fixed desktop-entry encoding for names, executable paths and startup arguments.
Percent signs, backslashes, quotes and line breaks preserve their literal values;
pass paths and arguments without pre-escaping them. The API is unchanged.

**Project creation**

`proton_cli new` delegates to `moon-new` and downloads the selected template from
Proton's `main` branch. It retains the destination path, `--template` and
`--author`. Creation no longer prompts or runs `moon check`. Git initialization
follows moon-new's behavior.

Projects can also be created directly with `moonx moonbit-community/moon-new`,
using `--template moonbit-community/proton --branch main` and
`--subdir templates/minimal` or `--subdir templates/isomorphic`.
Use `--user` in place of the CLI's `--author`.

Remove the old title, identifier, window size, check, Git, dry-run and confirmation
options. Customize the generated configuration and source files instead; run
checks explicitly. See the [new command](../command-line-interface/commands.md#new).

## 0.6.0

0.6.0 adds runtime window creation and authenticated file downloads, changes clipboard and keep-awake APIs to asynchronous operation, and fixes Windows monitoring. Existing applications using the affected APIs need the migrations below.

**Runtime window creation (breaking API change)**

`WindowManager.create(id, config)` creates independent windows at runtime from a reusable `WindowConfig`, including in single-instance applications. Window IDs no longer require startup declarations. Each instance has its own views, command identity and cleanup; stale handles remain invalid after an ID is reused.

Replace `windows.open(id)` with `windows.create(id, config)`. Remove delayed `add_window(..., open_on_start=false)` declarations and keep the configuration at the creation site instead. `App.add_window(id, config)` remains a startup convenience; `open_on_start` and `UnknownWindow` are removed. Use `RendererTarget::entry_prefix` or `bundled_prefix` for explicitly authorized ID families, or retain exact-ID grants.

`NewWindowDecision::OpenInWindow(id)` now targets an existing instance. A new-window handler that needs a new instance must await `create` first. See [window management](../introduction/application-api.md#windows-and-browser-views) and the [multi-window example](../examples/45_bridge_multi_window.md).

**Windows screen monitoring**

Fixed missing display-resolution change notifications while screen watching is active. Watching works without a visible application window.

**Authenticated file downloads**

The `moonbit-community/proton_ext/net` package adds the host-side async function
`download(url, destination, headers?, overwrite?, on_progress?)`. Applications
can download binary files with an `Authorization` header without buffering the
whole response or transferring file contents through IPC.

Downloads support progress and task cancellation. The destination's parent
directory must exist; an existing file is replaced only with `overwrite=true`,
after the new content has been fully saved. Destination paths preserve POSIX
symlink-plus-`..` traversal and Windows directory junctions and explicit extended
path prefixes. Overwriting a final symlink replaces the link itself without
changing its target.
Normal return confirms success;
failures raise `DownloadError`. Only HTTP 200 is accepted; redirects and partial
downloads are not supported. Downloads temporarily request identity encoding
by default and reject compressed responses until an upstream HTTP decoding fix
is available; servers must return unencoded content.

This adds no frontend command or filesystem grant to `net.capability()`.
Existing browser-managed `WebContentsHandle.download_url()` behavior is unchanged.
See [host networking](../introduction/application-api.md#extensions-and-capabilities)
for usage and cancellation semantics.

**Keep-awake lifecycle**

Linux keep-awake acquisition now waits for confirmed inhibition instead of
assuming a running helper has acquired the lock. Acquisition and cleanup are
asynchronous; exited helpers no longer report active protection.

Direct users of `proton_keepawake` must call async `acquire(tasks, ...)` with an
owning task group and async `release()`. `with_keepawake` now accepts an async
callback, releases protection on scope exit and cancels the callback if the Linux
helper exits unexpectedly. The frontend extension commands are unchanged and
own this lifecycle automatically. See [keep-awake usage](../introduction/application-api.md#extensions-and-capabilities).

**Clipboard access (breaking API change)**

Direct users of `proton_clipboard` must call `read_text()` and `write_text(text)` from an async context. Return values remain `Result`; operational failures are `Err(String)`, while cancellation propagates through the async runtime. The frontend extension commands are unchanged.

macOS uses the native pasteboard. Linux continues to use `wl-clipboard`, `xclip`, or `xsel`; pipe I/O and process waits now yield to the event loop. Cancellation stops and reaps the invoked tool. A successful write preserves the clipboard owner needed for later pastes.

**Windows power monitoring**

AC and onboard-battery notifications now produce `OnAC` and `OnBattery` correctly; UPS and unknown sources no longer produce misleading events. Idle-time queries no longer count the high bits of system uptime as idle time after the 32-bit last-input counter wraps. The counter still cannot distinguish idle intervals spanning a full period of about 49.7 days.

**Upgrading**

Once 0.6.0 is published, update the CLI and application `proton_*` dependencies together. Migrate window creation and direct clipboard/keep-awake calls as described above, run `proton_cli cef setup`, and rebuild packaged applications with the matching helper. The MoonBit `latest` toolchain requirement and CEF version are unchanged. Installing the CLI does not rewrite existing application source.

[Complete changes](https://github.com/moonbit-community/proton/compare/c63c9d2963551802481f4b2f13094afcce9222a5...91ffc6210878af84a639d773efdc71669dc47430)

## 0.5.1

0.5.1 fixes resource loading, filesystem link operations, monitor startup and update-manifest decoding. It adds macOS/Linux shell operations and a shared Rabbita query package. Despite the patch version, direct users of the power-monitor, shell and updater modules need the source migrations below.

**API changes and migration**

| Area | Previous API | 0.5.1 |
| --- | --- | --- |
| Power-event watching | `start_watching()` / `stop_watching()` | Run the work that needs events inside async `with_watching(callback)`. Returning, raising or cancelling ends watching and waits for cleanup; call `destroy()` only after the scope ends |
| Native shell operations | Synchronous `open`, `reveal_item`, `trash_item` returning `Result` | Call in an async context; success returns `Unit`, failure raises `ShellError`. `beep()` is unchanged |
| Manifest decoding | `Manifest::from_json(Json)` | Pass the original document text to `Manifest::parse(text)` so integer precision is preserved |

The Proton power-monitor extension owns its watching scope automatically. Its `watch_status()` now includes `Starting`; update exhaustive matches. Linux startup can be cancelled during connection, authentication or subscription and has a five-second deadline. A bus disconnection ends the scope rather than leaving it marked as watching. See [capability contracts](../introduction/application-api.md#extensions-and-capabilities).

New isomorphic projects import `moonbit-community/proton_rabbita/query` instead of generating `frontend/internal/query`. Existing projects can replace that local import with the public package, review local customizations, and remove the local implementation. `create`, `state`, `set_input` and `refresh` retain their usage. The package owns component reads, subscriptions and cancellation, without a shared cache or automatic retries. [Isomorphic tutorial](../tutorial/isomorphic.md)

**Behavior changes and fixes**

- **HTML resources:** `file` and `asset` serve the original document at its filename URL under `https://proton.localhost/`. The entry directory is the resource root, so relative resources use browser URL resolution. Proton no longer rewrites HTML or inserts `<base>`; declare a base in the document when needed. The constructors are unchanged. [Entry sources](../introduction/application-api.md#application-lifecycle)
- **Filesystem links:** content operations authorize resolved targets; removal and rename authorize and operate on the link itself. Recursive `rmdir` rejects a final symlink. Windows rename now preserves the link target with async 0.22.5. [Filesystem grants](../introduction/application-api.md#extensions-and-capabilities)
- **Desktop shell:** opening and revealing items work on macOS and Linux as well as Windows. External-tool waits yield to the application event loop and participate in cancellation. Linux requires `gio` and, for revealing items, `dbus-send` with a compatible file manager. [Environment requirements](../introduction/installation.md)
- **Screen monitoring:** Linux reports `Watching` only after registration succeeds; immediate events and startup errors are no longer lost in the startup race.
- **Update manifests:** `size` is decoded exactly from its original integer text over the positive `Int64` range. `size` and `schema_version` reject fractional and exponent notation, including values that floating-point parsing could round to integers. [Update download contract](../introduction/application-api.md#application-updates)

**Upgrading**

Use the MoonBit `latest` toolchain channel described in [environment requirements](../introduction/installation.md). Update the CLI and application `proton_*` dependencies to 0.5.1, apply the migrations above, then run `proton_cli cef setup` and rebuild packaged applications. Async advances to 0.22.5; Rabbita remains 0.16.4 and Warren remains 0.4.5. CEF is unchanged, but the helper is release-specific. Installing the CLI does not rewrite existing applications.

[Complete changes](https://github.com/moonbit-community/proton/compare/824db7a1acf20fa54d111145c321e464e30dbbae...18915e6b3c852b760dee6550f066f46d95a1248d)

## 0.5.0

0.5.0 changes application configuration to MoonBit cascade syntax, replaces paired lifecycle hooks with scoped setup and cleanup, and assigns browser decisions to their owning page or session. It also changes the application update protocol. Existing applications need source changes.

**Breaking changes and migration**

| Area | 0.4.0 | 0.5.0 |
| --- | --- | --- |
| App configuration | Configuration methods return `App`; chain with `.` | Methods return `Unit`; use `..config(...)`, `..commands(...)`, etc. Keep `.` for queries and `run()` |
| Application lifecycle | `app_lifecycle(on_start=..., on_shutdown=...)` | `setup(context => { ... })`; retain state in closures and register teardown immediately with `context.add_cleanup(...)` |
| Window lifecycle | `window_lifecycle(on_ready=..., on_close=...)` | `setup_window(context => { ... })` and `WindowContext.add_cleanup`; reopening creates a fresh scope |
| Quit decisions | `on_before_quit`, `on_will_quit` | `set_before_quit_handler`, `set_will_quit_handler`; each replaces the previous handler |
| Session decisions | `on_certificate_error`, `on_media_permission_request`, `on_download_request` | `set_certificate_error_handler`, `set_media_permission_handler`, `set_download_handler` |
| General permission hook | `on_permission_request`, `PermissionRequest` | Removed; register the specific certificate and media handlers |
| Window closing | `App.on_window_close_request` | `WindowConfig.close_handler` for each window |
| Navigation / new windows | Application-wide `on_navigation_request`, `on_new_window_request` | `WebContentsPolicy` on `WindowConfig` or `ViewConfig`; children do not inherit parent policy |
| Creation and final quit observers | Async `on_session_created`, `on_window_created`, `on_web_contents_created`, `on_quit` | Synchronous, non-raising callbacks; use setup/cleanup for awaited work |
| Handle representation | Public function-valued implementation fields | Runtime-created handles with methods; remove field-based dispatch or synthetic handle construction |
| Updates | Separate `revision`, schema 2, `rsa-sha256:<modulus>:<exponent>` keys | Application `version`, schema 3, standard `PUBLIC KEY` or `RSA PUBLIC KEY` PEM text |

Navigation decisions are now **synchronous** and cannot suspend or raise. They allow or deny the original main-frame navigation, including the initial load, cross-origin requests and intercepted `blob:` navigation. Proton no longer cancels and replays an allowed navigation. Await user confirmation before issuing an application-controlled `load_url` when asynchronous confirmation is needed. New-window, close, quit, certificate, media and download decisions remain asynchronous. [Callback contracts](../introduction/application-api.md#host-callback-contracts)

`on_*` observers append; `set_*_handler` decisions replace. Async observers do not hold up the source operation and may overlap. Setup callbacks are awaited and may fail startup. Cleanup registered with `add_cleanup` runs after scoped tasks stop, in reverse order and under cancellation protection, including after partial setup failure or cancellation. Replace no-op start/stop callbacks with only the setup or cleanup actually needed. [Lifecycle](../introduction/application-api.md#application-lifecycle)

When matching `LifecycleHookError`, application cleanup now reports `ApplicationShutdown(detail)` without a hook index; window cleanup reports `WindowClose(window, detail)` using the window declaration ID.

For update publishers, remove `--updater-revision` and the `updater public-key` command. `package --version` or `package.version` is the single application release value; a rebuild with the same version is not an update. Export a standard PEM public key with OpenSSL. Keep schema 2 endpoints available for old clients; migrating those installations to schema 3 requires a manual upgrade or a deliberately prepared transition release. [Update packaging](../command-line-interface/packaging.md#update-artifacts-and-metadata)

The unused `proton/catalog` package is removed. Extension operations continue to come from registered command bindings; capabilities remain the application registration and authorization entry point.

**Additions and fixes**

- **Dock and badges:** `ApplicationContext` gains numeric badge operations and macOS Dock text/attention APIs. Numeric badge setters return `false` on unsupported platforms; macOS-only Dock operations raise `UnsupportedPlatform` elsewhere. [Platform contracts](../introduction/application-api.md#process-control-and-metrics)
- **Creation notifications:** views added from a creation observer are announced once; a view removed by an earlier observer is not announced afterwards. Window cleanup rejects late navigation without invoking application policy against resources being released.
- **Windows input focus:** native-frame activation and `focus()` restore browser keyboard/IME focus, including the previously focused visible child view. This addresses a lost-focus path; applications should still verify their affected IME scenarios on Windows.
- **Update downloads:** macOS selects app ZIPs, Windows selects NSIS installers, and Linux selects AppImages. HTTPS downloads resolve relative redirects with a five-hop limit. Artifacts stream to disk with authenticated `Int64` sizes; the 1 MiB metadata limit does not cap application artifacts. Header and received-byte checks reject size mismatches. [Download contract](../introduction/application-api.md#application-updates)
- **CDP automation:** the optional native `proton_cdp` package follows the same release version. It connects to an existing debugging endpoint and does not launch a Chrome window unless a launch operation is explicitly requested. [CDP reference](../command-line-interface/debugging.md#native-cdp-automation)

**Upgrade requirements**

Use the stable MoonBit toolchain with explicit `Int32` / `UInt32` support (2026-10-12 or newer). The isomorphic template uses Warren 0.4.5; Rabbita remains 0.16.4 and async remains 0.22.4. CEF is unchanged, but the helper is release-specific.

Update the CLI and application `proton_*` dependencies to 0.5.0, run `proton_cli cef setup`, migrate the calls above, and rebuild packaged applications so their helper and version metadata match. CLI installation does not rewrite existing source or updater endpoints. [Complete source changes](https://github.com/moonbit-community/proton/compare/ae8f69ed637afda91b79b7c06f95ffb4d6a954d2...6c7c6810b492ffdc57b0908fc926d67db6656eef)

## 0.4.0

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
