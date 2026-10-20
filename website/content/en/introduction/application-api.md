# Application API reference

The root `moonbit-community/proton` package is the public application facade. Use the builder before `run`; use context and handle operations while the application is running. CLI project metadata does not replace runtime configuration.

| Area | Owner / entry | Reference |
| --- | --- | --- |
| Startup, readiness, quit, task cleanup | `App`, `ApplicationContext`, lifecycle hooks | [Lifecycle](#application-lifecycle) |
| Window declarations, instances, child browsers | `App`, `WindowManager`, `WindowHandle`, `ViewHandle` | [Windows](#windows-and-browser-views) |
| Request/response communication | contract, registrar, client | [Commands](#commands) |
| Frontend notifications and subscription lifetime | emitters, client subscriptions | [Events](#events) |
| Host operations and renderer authorization | `App.capability`, extension-specific scope | [Capabilities](#extensions-and-capabilities) |
| Cookies, browser storage, proxy | `SessionHandle`, startup builder | [Browser sessions](#browser-sessions) |
| Signed application updates | `App.update_channel`, `PendingUpdate` | [Updates](#application-updates) |
| Process ownership and activation | single-instance builder, context methods | [Process control](#process-control-and-metrics) |
| Paths, files and build metadata | project configuration and application paths | [Configuration](../configuration/project.md) |

For the complete set of methods, overloads, typed errors and defaults, use the [versioned API index](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/proton/pkg.generated.mbti). This reference describes when to use each entry point, which object owns its state, and how it behaves during startup, cancellation and shutdown.

## Application lifecycle

`App` configures an application before startup. It is created through the root Proton facade and executed through the MoonBit async runtime. Proton installs its native event-loop integration during initialization; application code does not install or poll a separate UI loop.

**Entry sources**

| Constructor | Entry |
| --- | --- |
| `html(title, html, ...)` | Inline HTML document |
| `url(title, url, ...)` | URL |
| `file(title, path, ...)` | Local HTML file |
| `asset(title, path, ...)` | Managed application asset entry |

Each returns an `App` builder. Shared options include width, height, debug mode and resizability. To replace the primary window declaration, pass a new `WindowConfig` to `App.main_window(config)`; the entry belongs to that configuration.

**Configuring an application**

Configuration methods, including `config`, `debug`, `add_window`, and `on_*` hook
registration, modify the existing `App` and return `Unit`. Use `..` to retain the
application value across configuration calls:

```moonbit
let app = @proton.html("Hello", "<h1>Hello</h1>")
  ..config(@proton.load_config())
  ..debug()

app.single_instance()
app.run()
```

A direct call such as `app.single_instance()` returns `Unit`. Constructors still
return `App`; queries such as `app.name()` retain their result types. `run()` and
`run_or_abort()` remain ordinary async calls.

To migrate an existing builder chain, change its configuration calls from `.` to
`..`. Keep `.` for queries and the final `run()` / `run_or_abort()`. The return-type change does not alter configuration validation or registration order. Lifecycle and callback migrations are described below.

**Identity**

`@proton.load_config()` returns the complete typed `AppConfig` and reports loading errors immediately. Read `identifier`, `backend`, `frontend`, and `package_config` directly from this value. Install it with `app.config(config)`, which is mutually exclusive with `app.identifier(...)`. The identifier is stable application identity, distinct from the window title, product name, and version.

`app_path()`, `resource_dir()` and `is_packaged()` describe the execution environment. Development paths and packaged resources have different locations; frontend URLs are not backend filesystem paths.

**Hooks and owned state**

| Hook | Meaning |
| --- | --- |
| `setup(callback)` | Awaited application setup before initial windows open |
| `setup_window(callback)` | Awaited setup for each ready window instance |
| `WindowConfig.close_handler` | Async allow/deny decision before window closure |

`setup` and `setup_window` append awaited lifecycle operations; they are not `on_*` observation callbacks or replaceable `set_*_handler` decisions. Setup errors fail initialization. Register cleanup only while its scope is active.

Register resource cleanup with `ApplicationContext.add_cleanup` or `WindowContext.add_cleanup` immediately after acquisition. Cleanup waits for child tasks to stop, runs in reverse registration order, and is protected from cancellation. Already registered cleanup also runs if setup later fails or is canceled; failures are collected without skipping remaining cleanup. A reopened window has a new scope.

Application and window contexts expose task groups and window management. Window contexts additionally expose their handle and event emitter. A window's state must not outlive the resources it refers to.

**Running the application**

Calling `run()` starts the configured application and awaits its lifecycle. It is async and raises `AppRunError` on failure. `run_or_abort()` instead reports a failure and aborts. Startup, task ownership and exit behavior are described below.

**Startup order**

Startup validates configuration, resolves identity and paths, initializes logging, and acquires the single-instance lock when configured. A secondary instance that forwards its activation returns without creating an application runtime.

For the primary instance, synchronous `on_session_created` observers run before awaited `setup` callbacks. Proton then opens declared startup windows that setup did not already open, waits for the required bridge initialization, and awaits `setup_window` for each initial window. Application readiness follows successful initial activation; configuring a window or receiving a creation notification does not establish readiness.

An application setup callback may await `context.windows().open(id)`. A committed exit stops startup. A denied quit request leaves the application running; requesting quit is not itself a committed exit.

**Task and cleanup ownership**

Use application task groups for work that belongs to the application, and window task groups for work that belongs to a window. Their scopes are canceled and drained on shutdown; detached work outside these scopes is not made lifecycle-safe by holding a window handle.

Setup callbacks return `Unit`; resources stay in ordinary closures. Calling `context.add_cleanup` immediately registers a cleanup operation with that running scope. If setup fails or is canceled after registration, cleanup still runs. Cleanup cannot spawn new tasks in the terminating group. Reported cleanup failures accompany the original failure in `AppRunError`, rather than replacing it. Application cleanup diagnostics use `ApplicationShutdown(detail)`; window cleanup diagnostics use `WindowClose(window, detail)` to identify the owning instance declaration.

Window setup and its registered cleanup own per-window state; creation and browser event callbacks report observations. A renderer can navigate or crash while its native window remains alive. Page tasks and subscriptions must therefore also respect page lifetime, as described in [commands](#commands) and [events](#events).

**Quit decisions and forced exit**

| Operation | Contract |
| --- | --- |
| `context.quit(exit_code=0)` | Requests orderly shutdown; cancelable |
| `context.exit(exit_code=0)` | Forces shutdown and process termination, including status zero |
| `handle.close()` | Requests closing that window; subject to its close interceptor |

The default `LastWindowClosedPolicy::Quit` requests shutdown after the last window closes; `KeepRunning` keeps the application running until an explicit quit or exit. Browser and child-view teardown must finish before normal runtime shutdown completes.

An orderly quit runs `set_before_quit_handler`, closes windows through their close decisions, then runs `set_will_quit_handler` after windows close. `ApplicationQuitDecision::Prevent` cancels the quit; a denied window close also cancels the request. Cancellation does not recreate windows that have already closed. `on_quit` observes the final exit code before runtime teardown and is not a veto point.

Forced exit bypasses cancelable decisions, including an already pending decision, but still performs the final quit notification and runtime cleanup. It is not equivalent to externally killing the process. Scheduled relaunches are started after cleanup and before process termination.

On successful ordinary zero-status quit, `App.run()` returns. A successful nonzero quit terminates with that status; forced exit terminates even for zero. Code following `run()` must not be the only place for required shutdown cleanup.

## Commands

A command is a typed request/response operation across the renderer–host boundary. Payloads are serialized; a shared MoonBit type does not share memory or execute backend code in the renderer.

**Contract and binding**

| API | Contract |
| --- | --- |
| `proton_contract.command[Request, Response](name)` | Declares a typed application route; does not register a handler |
| `App.commands(register, targets?)` | Installs application command bindings for selected renderer targets |
| `CommandRegistrar.bind(command, handler)` | Binds an async handler taking `(CommandContext, Request)` and returning `Response` |
| `proton_client.invoke(command, request)` | Async frontend invocation; returns `Response` or raises `ClientFailure` |
| `proton_rabbita.invoke(...)` | Adapts completion/failure to Rabbita commands |

On the backend, `Request` must implement `FromJson` and `Response` must implement `ToJson`. The frontend requires the inverse conversions. Contract and registration errors are distinct from failures of a running request. Application route names must be unique and valid; descriptors are validated during binding and invocation.

The handler context identifies the caller and supports `emit_to_caller`. A handler may await backend work. Business outcomes such as validation rejection can be modeled in the response type rather than thrown as transport failures.

**JavaScript interface**

The injected bridge exposes application methods as `window.__MoonBit__.app.<name>(request)`. Calls return promises; failures reject them. Application routes use `app:`; extension operations use `ext:`. An ordinary browser page has no injected native bridge.

**Request scope and page invalidation**

Each accepted request has its own command scope. Awaited work, child tasks, and deferred cleanup in that scope belong to the request. A handler or its scoped cleanup failing is a request failure (`handler_failed`), not an instruction to terminate the application. Runtime infrastructure failures remain application errors.

Navigation, renderer termination, or bridge failure invalidates the old page's pending requests. Once a bridge attempt has failed, that failed page cannot start new application commands until a new valid attempt is established. Initialization-time requests are permitted; waiting for every request until ready would prevent legitimate initialization work.

Caller cancellation and page invalidation stop waiting and request cancellation of outstanding work. Neither rolls back business side effects already performed. Use application-level operation identifiers or transactions when a retry must not duplicate an operation. Do not infer successful execution from successful message submission.

**Cancellation**

`proton_client.invoke_with_callbacks` returns a cancellation function. It cancels response observation and requests transport cancellation; late responses are ignored. Async `invoke` also cancels the pending request when its task is cancelled. The request scope described above governs the backend work; cancellation does not undo completed side effects.

**Client failures**

| Variant | Meaning |
| --- | --- |
| `BridgeUnavailable` | Native bridge is absent |
| `InvalidContract` | Invalid command/event descriptor |
| `RemoteFailure` | Backend rejection with code, message and optional detail |
| `TransportFailure` | Communication failure |
| `ResponseDecode` | Response does not decode as the declared type |
| `RequestCancelled` | The pending request was cancelled |

**Command error codes**

`RemoteFailure.code` identifies the failure independently of its message:

| Code | Meaning |
| --- | --- |
| `invalid_payload` | The request does not match the command's input type |
| `unknown_op` | The requested operation is not registered |
| `handler_failed` | The command handler raised an error |
| `host_closed` | The command host has closed |
| `permission_denied` | The page is not permitted to invoke the operation |

Handle codes rather than parsing message text, and handle unrecognized codes as
other remote failures. Backend diagnostics remain in application logs. Development mode
also includes them in `detail`; `message` remains
a caller-facing description. Expected business outcomes belong in the command's
response type.

**Resource limits**

Proton does not impose a fixed payload-size limit on commands. Payloads are serialized as JSON and remain subject to memory and underlying transport constraints. Large messages increase serialization, copying and parsing costs.

Request concurrency has no global fixed admission limit in 0.5.0. Applications still need to bound expensive work according to their own resource and ordering requirements; the bridge does not serialize unrelated business operations into a transaction.

## Events

Events are typed host-to-renderer notifications with no response value. `proton_contract.event[Payload](name)` declares a descriptor; it does not install a listener or retain previous notifications.

**Destinations**

| API | Destination and lifetime |
| --- | --- |
| `CommandContext.emit_to_caller(event, payload)` | The page that issued the current command |
| `WindowContext.events()` | Produces a window event emitter |
| `WindowEventEmitter.emit(event, payload)` | The associated window while it remains alive |

Host payloads require `ToJson`. Window emitters belong to window lifetime; a saved emitter must be removed from application state when that window closes. Emission is not an implicit broadcast to all windows.

**Subscriptions**

`proton_client.subscribe(event, listener, failure)` decodes payloads through `FromJson` and returns a `Subscription`. `Subscription.close()` releases the listener. Subscription setup can raise `ClientFailure`; event decoding failures are reported as `EventDecode` through the failure callback.

`proton_rabbita.subscribe` integrates subscription ownership into Rabbita. Its options include a subscription key, retry count, ready command and client override; full signatures are in the [Rabbita API](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/rabbita/pkg.generated.mbti).

The JavaScript interface is `window.__MoonBit__.app.on(name, callback)`. The callback receives an event envelope containing `payload`; registration returns an unsubscribe function.

**Delivery semantics**

- Notifications missed before subscription are not replayed.
- Command responses and events are separate deliveries; their relative order is not an application synchronization contract.
- Listener disposal ends observation; events are not a durable queue or acknowledgment protocol.
- A notification that state changed can invalidate a frontend query. The authoritative snapshot is obtained through a command.

**Subscription lifetime and state synchronization**

A subscription belongs to the current renderer document or UI component. Close it when that owner is disposed. A reload creates a new document and requires a new subscription; keeping a native window alive does not preserve JavaScript listeners across reloads.

For state synchronization, subscribe before loading the initial snapshot, use events to invalidate that snapshot, and ignore responses from superseded queries. Subscribing first avoids a gap before the initial read, but does not turn two independent messages into an atomic transaction. Include a revision in application data when the consumer must detect stale snapshots or missed changes.

Application-level lifecycle notifications such as `on_window_created` and `on_render_process_gone` are host callbacks, not `proton_contract` frontend events. Register them on the App builder; use a command or explicit event if the frontend also needs that information.

The [event tutorial](../tutorial/events.md) demonstrates subscription and cleanup. The [Todo tutorial](../tutorial/isomorphic.md) demonstrates invalidation followed by a snapshot query.

## Windows and browser views

Window declarations belong to `App`; operations on a running window belong to `WindowHandle`. Browser navigation and developer tools belong to `WebContentsHandle`, obtained through `WindowHandle.web_contents()`.

**Identity and declaration**

The primary window ID is `main`. `App.add_window(id, config, open_on_start?)` declares secondary windows; their IDs must be nonempty, unique and different from `main`. Titles are display text and do not identify windows.

Secondary windows open at startup by default. `open_on_start=false` defers opening until `WindowManager.open(id)`. `ApplicationContext.windows()` and `WindowContext.windows()` expose the manager. All windows belong to one application runtime.

`WindowConfig(title, entry, ...)` holds dimensions, size hint, theme, titlebar style, traffic-light position, initial `views`, `close_handler`, and `web_contents_policy`. Use `App(config)` for the primary window, `App.main_window(config)` to replace its startup configuration, and `App.add_window(id, config, ...)` for secondary windows. Registrations snapshot the views array. The `html`, `url`, `file`, and `asset` shortcuts remain available for a simple primary window.

Window, view, and web-contents handles are runtime-created values. Use their public methods; do not construct them, copy their representation, or call the former function-valued implementation fields. Identity is available through `id()`, `window_id()` and optional `view_id()` as appropriate.

**Opening and instance identity**

`WindowManager.open(id)` is asynchronous and returns an activated `WindowHandle`. The id selects a declaration; it is not a permanent identity for every future native instance. After closing and reopening a declared window, obtain the new handle through `open` or `find`; an old handle does not become valid again.

Cancellation before activation commits discards the queued open or closes the instance created by that operation. After activation commits, the application owns the window: canceling the caller later does not close it. Unknown declarations and invalid window state produce window-session failures; task cancellation follows the async task's cancellation semantics.

`hide()` preserves the instance, browser, and associated work. `close()` initiates teardown and can be denied. Do not equate a close request with completed cleanup. Per-window state should be released by its lifecycle cleanup, not immediately after requesting close.

**Lookup and browser readiness**

`WindowManager.find(id)` returns the current active instance, including a window that is still starting. It does not wait for native browser initialization, page loading, or command bridge readiness. Obtaining a `WebContentsHandle` does not wait for these conditions either.

These are distinct conditions:

- Native browser initialization makes browser queries such as `WebContentsHandle.state()` available. During startup, a query can raise `WindowSessionError::OperationFailed` because the browser is not initialized. Do not assume that all browser operations are queued until initialization completes.
- Page loading concerns the current navigation. For work that needs a loaded page, observe `on_web_contents_event` for that window or view, then verify the expected URL and page state. `DidFinishLoad` reports a loading-to-idle transition; by itself it does not prove that the intended navigation succeeded. Handle `LoadFailed` separately.
- Command bridge readiness concerns communication with the current page. A browser handle or a load-completion event alone does not establish that the bridge is ready.

Coordinate operations with the condition they actually require. A fixed delay after `find()` is not a readiness guarantee, and navigation or closure can invalidate earlier observations.

**Runtime operations**

| Area | `WindowHandle` operations |
| --- | --- |
| Visibility and focus | `show`, `hide`, `focus`, `is_visible`, `is_focused` |
| Geometry | `bounds`, `set_bounds`, `position`, `set_position`, `content_size`, `set_content_size` |
| Window state | `minimize`, `maximize`, `restore`, `set_fullscreen` |
| Appearance | `set_theme`, `set_background_color`, `set_title`, `set_menu` |
| Lifetime | `close` |

Native operations can raise `WindowSessionError`. A handle is not valid indefinitely: window-owned state and retained event destinations must be released when the window closes. A hidden window is still alive.

**Close semantics**

`WindowConfig.close_handler` configures an async callback that receives the window handle and returns `WindowCloseDecision::Allow` or `Deny`. `WindowContext.add_cleanup` is cleanup after closure; it is not a veto hook. The default last-window policy is `Quit`. `KeepRunning` leaves the application running with no open windows and requires an explicit exit path. See [application lifecycle](#application-lifecycle).

**Child browser views**

`WindowConfig.views` declares initial views on either primary or secondary windows; `WindowHandle.add_view` creates one dynamically and returns `ViewHandle`. A view is a child browser hosted inside a window, not a second top-level window. Its bounds use a top-left origin; visibility and z-order are independent of the main page. `remove_view` removes a child. Closing the parent must also complete child-browser teardown.

**Browser and view boundaries**

Both `WindowHandle.web_contents()` and `ViewHandle.web_contents()` return `WebContentsHandle`. Navigation, script evaluation, zoom, audio, developer tools, printing, downloads and session access use that common handle. Child geometry, visibility, z-order and removal remain on `ViewHandle`; native window controls remain on `WindowHandle`. Child navigation does not navigate the main page.

Subscribe to `App.on_web_contents_event` for main-page and child-page events. Callbacks carry the common handle: `window_id()` identifies the owning window and `view_id()` is `None` for its main page. Handles remain bound to one native instance; reusing a declaration id does not revive an old handle. A child view does not receive the application command bridge.

`on_render_process_gone` covers both main pages and child views without requiring an extra `on_web_contents_event` subscription. Renderer termination invalidates page work; it is not a normal window close. Decide whether to reload or present recovery UI based on the reported details, and recreate page subscriptions after navigation.

A view declaration sets initial geometry; it does not provide automatic layout. Update its bounds when the parent content layout changes.

**PDF output**

`WebContentsHandle.print_to_pdf(path, options?)` is asynchronous and returns `Unit` after successful completion. Call it in an async context and handle failure at the call site; no completion-event subscription or request-id correlation is needed. Concurrent calls on main and child pages keep separate completion identities. Closing the page, losing its renderer, or ending the application wakes outstanding callers. Cancellation stops waiting, not the underlying native print job; the destination file may still be produced.

**Platform behavior**

`WindowThemePreference` controls a window's theme; `system_appearance()` reports system appearance. These are separate concerns. Titlebar styles and native controls differ by platform. Traffic-light positioning applies to macOS; the frontend layout must account for native controls when using an overlay titlebar.

`TitlebarStyle::Overlay` is available on macOS, Windows and Linux. In an overlay page, `await window.__MoonBit__.getTitlebarArea()` returns the usable titlebar area as `{ x, y, width, height }` in CSS pixels, or `null` when unavailable. Query it during layout and after resizing; the application applies the result to its CSS. Interactive controls inside draggable regions need `-webkit-app-region: no-drag`.

**Accessibility and headless execution**

Web content uses Chromium's native accessibility tree. Use semantic HTML, ARIA, keyboard navigation and visible focus. Accessibility follows the platform's policy by default; `App.accessibility(AccessibilityMode::AlwaysEnabled)` keeps the tree available throughout the runtime. See [platform accessibility behavior](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/proton/README.md#accessibility).

`App.headless()` or `PROTON_HEADLESS=1` selects off-screen rendering without native top-level windows. Native dialogs, menus, titlebars and other window-bound UI are unavailable. Linux still requires an X11 display, such as Xvfb. Browser automation and native-window behavior therefore require different validation environments.

## Extensions and capabilities

Extensions register reusable host operations. A renderer capability installs an extension's backend and grants a permission scope to selected renderer targets. Adding `proton_ext` as a module dependency only makes code available; it does not install handlers or grant access.

**Registration and targets**

`App.capability(capability, targets?)` configures installation and access. With no explicit targets, the grant applies to the main entry. `RendererTarget.entry(window=...)` and `RendererTarget.bundled(window=...)` select entry or bundled-page targets for a named window. Permissions do not implicitly become global merely because windows belong to one application.

Application commands use `app:` routes; extension operations use `ext:<extension>/<operation>`. JavaScript can invoke an installed operation through `window.__MoonBit__.core.invokeOp(route, request)`, which returns a promise.

**Filesystem scope**

`proton_ext/fs.capability` accepts `PermissionRoot` values pairing a host directory with permitted operations. The scope is configured by the backend; renderer requests cannot widen it.

| Property | Behavior |
| --- | --- |
| Relative root or request path | Resolved against `resource_dir()` |
| Path outside allowed roots | Rejected, including symlink escapes |
| Operation absent from root grant | Not authorized by that grant |
| Text payloads | UTF-8 |

Supported filesystem operation names include `read_file`, `write_file`, `mkdir`, `readdir`, `remove`, `rmdir`, `rename`, `realpath`, `exists`, `kind` and `size`. Canonical path checks and operations are serialized within the extension.

Content operations follow existing symbolic links only to targets inside an authorized root. Unresolved links are rejected, including when creating a file. `remove`, `rename`, and `kind(follow_symlink=false)` operate on the final directory entry while still resolving and authorizing its parent. Removing or renaming a link leaves its target unchanged. `rmdir` rejects a final symbolic link even for recursive removal; use `remove` for the link itself.

**Availability and errors**

A missing capability leaves its route unavailable. An installed extension can still reject a request because of scope, invalid arguments, a platform limitation or an operating-system failure. These failures are reported through the command bridge; installation does not imply that every native operation will succeed.

Capability-specific scope types are documented in the extension API; platform coverage is summarized below.

**Platform differences and selection**

These are key boundaries of implemented 0.5.0 capabilities, not a promise of availability without desktop services:

| Capability | macOS | Windows | Linux |
| --- | --- | --- | --- |
| Files, paths, host HTTP, child processes | Supported | Supported | Supported |
| Native dialogs, text clipboard | Supported | Supported | Depends on desktop session / GTK and related backends |
| System notification extension | Supported | Not implemented | Not implemented |
| Tray | Menus and platform events | Click, right-click, double-click and menus | Requires AppIndicator / Ayatana and desktop support |
| Desktop sources and thumbnails | Displays; thumbnails require screen-recording permission | Visible titled windows and GDI thumbnails | X11/RandR displays; thumbnails are null |

Capability grants are separate from operating-system authorization. Declaring a screen or media capability does not grant OS privacy permission. Handle OS denial, unavailable backends and missing application grants separately. Check support where provided, such as the tray capability; menu events are more portable than platform mouse gestures.

**Host networking and child processes**

The net extension performs host HTTP requests and returns status, headers and UTF-8 text. It is not browser fetch, does not share the browser cookie jar and does not follow redirects automatically. Its text response is not a lossless binary transfer interface. Processes spawned by the process extension belong to its application lifetime: wait collects handles, kill still needs wait, and application shutdown cancels and reaps remaining children.

See the [extension API](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/extensions/pkg.generated.mbti) for the complete inventory and scope types. Check target grants, OS permission and platform backend support independently.

## Host callback contracts

`on_*` methods append observers. `set_before_quit_handler`,
`set_will_quit_handler`, `set_certificate_error_handler`,
`set_media_permission_handler`, and `set_download_handler` each replace one
decision handler. Async decisions are awaited; async notifications do not block their
source operation and may overlap while suspended. No completion order is
promised. Handle expected errors inside these `noraise` callbacks; holding a
handle does not extend the lifetime of its native object.

**Observers**

All observers return `Unit` and cannot raise. Register multiple observers with repeated `on_*` calls.

| Method | Callback arguments | Execution |
| --- | --- | --- |
| `on_session_created` | `ApplicationSession` | Synchronous; before application setup |
| `on_window_created` | `WindowHandle` | Synchronous; instance created, browser not necessarily ready |
| `on_web_contents_created` | `WebContentsHandle` | Synchronous; main page or child instance created |
| `on_quit` | `ApplicationContext`, exit code | Synchronous; exit committed, before runtime teardown |
| `on_window_event` | `WindowHandle`, `WindowEvent` | Async |
| `on_web_contents_event` | `WebContentsHandle`, `WebContentsEvent` | Async |
| `on_render_process_gone` | `WebContentsHandle`, `RenderProcessGoneDetails` | Async; covers main and child renderers without another event subscription |
| `on_download_event` | `WebContentsHandle`, `DownloadEvent` | Async |
| `on_launch_input` | `ApplicationContext`, `RuntimeLaunchInput` | Async |
| `on_system_appearance_change` | `SystemAppearance` | Async |
| `on_thumbar_button_click` | `WindowHandle`, button ID | Async |
| `on_update_available` | `PendingUpdate` | Async |

**Decision handlers**

| Registration / field | Result | Default |
| --- | --- | --- |
| `App.set_before_quit_handler` | `ApplicationQuitDecision` | Allow quit |
| `App.set_will_quit_handler` | `ApplicationQuitDecision` | Allow quit |
| `App.set_certificate_error_handler` | `BrowserPermissionDecision` | Deny |
| `App.set_media_permission_handler` | `BrowserPermissionDecision` | Deny |
| `App.set_download_handler` | `DownloadDecision` | Deny |
| `WindowConfig.close_handler` | `WindowCloseDecision` | Allow close |
| `WebContentsPolicy.navigation_handler` | `NavigationDecision` | Allow navigation |
| `WebContentsPolicy.new_window_handler` | `NewWindowDecision` | Deny new browsing context |

All decision callbacks except navigation are async and `noraise`; navigation is synchronous and `noraise`. The context or contents argument identifies the request owner, not a grant of additional lifetime.

Creation notifications (`on_session_created`, `on_window_created`,
`on_web_contents_created`) and final `on_quit` notifications run synchronously
in registration order. They are not asynchronous setup or cleanup hooks.
Creation does not imply page readiness or run before initial navigation. Use
`setup` and `setup_window` for awaited setup; register cleanup with `context.add_cleanup`.

`WebContentsPolicy(navigation_handler?=..., new_window_handler?=...)` belongs to
one page. Supply it through `WindowConfig.web_contents_policy` for a window's
main page or `ViewConfig.web_contents_policy` for a child, including a view added
at runtime. Policy is installed before the first load. Children do not inherit
these handlers; share a policy value explicitly when desired. Navigation is
allowed by default; new browsing contexts are denied by default.

`navigation_handler` is synchronous and cannot suspend or raise. It returns
`NavigationDecision::Allow` or `Deny` before the original navigation proceeds,
for main-frame document loads, including initial loads, cross-origin requests and intercepted `blob:` navigations. Iframe navigation is not routed through this handler.
Keep it short because it runs on the UI thread. Same-document changes such as
hash navigation and `history.pushState`, and subresource loads, are not intercepted. For asynchronous
confirmation, await the confirmation before calling `contents.load_url(url)`.
`new_window_handler` remains asynchronous.

```moonbit
let policy = @proton.WebContentsPolicy(navigation_handler=fn(_contents, request) {
  if request.url.has_prefix("https://proton.localhost/") ||
    request.url.has_prefix("https://example.com/") {
    @proton.NavigationDecision::Allow
  } else {
    @proton.NavigationDecision::Deny
  }
})
let app = @proton.App(@proton.WindowConfig(
  "Restricted page",
  @proton.AppEntry::Html("<a href='https://example.com/'>Open example</a>"),
  web_contents_policy=policy,
))..config(@proton.load_config())
```

Use the same policy in `ViewConfig(..., web_contents_policy=policy)` to apply it to a child. A window entering cleanup rejects navigation without calling its policy again; do not retain a handler as a way to continue window-owned work during cleanup.

`WindowConfig.close_handler` belongs to that window and also participates in
application quit. An absent handler allows closing. Certificate, media and
download decisions apply to the single application session and default to deny;
there is no general permission handler overriding the specific handlers.
Pending decisions are canceled when their owner closes or becomes invalid;
forced exit supersedes cancellable close/quit decisions.

## Browser sessions

A browser session contains cookies, cache, authentication state and web storage. Obtain its handle from `ApplicationContext.session()` even before a window exists, or from any `WebContentsHandle.session()`. Both access the same application session. Closing a page does not invalidate the session, and clearing shared data affects the other pages using that profile.

**Startup settings**

`App.session_partition(name)` selects a persistent profile below the application's sessionData directory. It is application startup configuration, not a per-window incognito switch. Windows in the application runtime use that configured profile. Use stable application identifiers and partition names to preserve data across launches.

`App.proxy(server, bypass?)` configures Chromium's startup-wide proxy. It cannot be changed during the run. This controls browser traffic; it does not configure every MoonBit networking library in the host.

The `on_session_created` callback exposes the partition and resolved data path before application start hooks create their windows. Packaged resources and the browser profile are different paths; do not put writable profile data inside the application bundle.

**Operations**

| API | Effect |
| --- | --- |
| `get_cookies` | Asynchronously reads matching cookies; optional URL and HttpOnly selection |
| `set_cookie` | Sets a cookie with URL, name, value and optional domain/path/security attributes |
| `delete_cookies`, `flush_cookies` | Deletes selected cookies or flushes persistent cookie storage |
| `clear_cache`, `clear_storage_data` | Clears cache or selected web-storage kinds |
| `clear_auth_cache` | Clears cached HTTP authentication |
| `clear_certificate_exceptions` | Clears certificate exception state |
| `close_all_connections` | Closes session connections |

Operations raise `SessionError` and require a live application runtime, not a live page. Handles remain usable with no windows under `KeepRunning`; application teardown wakes pending cookie readers and invalidates retained session handles. Concurrent cookie reads are independent. A clearing operation does not erase application-owned files or implement an application logout protocol; invalidate backend credentials and UI state separately.

Full attributes and `StorageDataKind` variants are in the [API reference](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/proton/pkg.generated.mbti).

## Application updates

Application updates replace the distributed application, not the development CLI or Mooncakes dependencies. Configure `App.update_channel(endpoint, public_keys, check_on_launch?, freshness_days?)` before running the app.

**Channel and checks**

The endpoint must use HTTPS and there must be at least one trusted RSA public key of at least 2048 bits. Automatic checking defaults to enabled; manifest freshness defaults to 30 days and must be positive. Pass each public key as PEM text (`PUBLIC KEY` or `RSA PUBLIC KEY`), not as a file path. The runtime parses the PEM and validates the RSA key; private keys and certificates are rejected. The public-key array allows more than one trusted signing key during rotation.

The automatic check runs after successful startup and reports failures through logging without making startup fail. For explicit checks, use `ApplicationContext.check_for_update()` and handle its result and errors. `NotConfigured` is distinct from `UpToDate`; a context used after its application ends no longer has an active channel.

An offered `PendingUpdate` has passed manifest trust, freshness and version checks. It exposes version, size and optional notes URL, but the artifact has not yet been downloaded.

**Download and installation**

`PendingUpdate.download()` writes the artifact into a private stage and verifies its size, digest and signature. It does not replace application files or exit on any platform. Repeated downloads of the same prepared version are a no-op.

Metadata, signature and artifact downloads follow at most five redirects, resolving relative locations and requiring HTTPS for every target. Manifest and detached-signature responses are each limited to 1 MiB. Artifact bodies are streamed to staging and are not subject to that metadata limit; the positive `Int64` size in the authenticated manifest is the expected byte count. A conflicting `Content-Length` or an incomplete/oversized body fails the download. Self-update artifacts must be an app ZIP on macOS, an NSIS installer on Windows, or an AppImage on Linux. DMGs remain available for manual installation.

After downloading, call `ApplicationContext.quit_and_install()` when the user chooses to apply the update:

```moonbit
match context.check_for_update() {
  Available(update) => {
    update.download()
    context.quit_and_install()
  }
  UpToDate | NotConfigured => ()
}
```

The request follows the [quit lifecycle](#application-lifecycle). Preventing quit cancels installation and retains the download for another attempt. Once quit is accepted, Proton closes the runtime and completes cleanup before installation. If single-instance mode is enabled, its reservation stays held throughout replacement. Windows transfers the reservation to its NSIS installer before the old process exits; the installer releases it after installation. macOS and Linux retain the lock while replacing the application artifact, then release it before launching the replacement. Successful handoff terminates the old process, including when the exit code is zero.

The method returns when the request is accepted, not when the new version is ready. Missing downloads and conflicting exit or relaunch requests fail immediately; later installation or launch failures are reported through `App::run()`. A forced `exit()` supersedes a pending update request. A pending update exit refuses explicit release of a held single-instance lock; an application that already released its configured lock cannot request installation. Ordinary quit discards the download without installing. Cleanup failure prevents installation. Old managed update artifacts are removed after the replacement successfully starts.

**Publisher responsibilities**

Keep the application identifier stable and increase `package.version` for every update. Versions use three non-negative `Int32` components (`major.minor.patch`), compared numerically without leading zeros; pre-release and build suffixes are not supported. A rebuild with the same version is not an update. The updater metadata options in [CLI package](../command-line-interface/commands.md#package) describe the artifact location and publication instant; the manifest uses the packaged application version.

Schema 3 replaces the old revision-based schema 2: retain the old endpoint for existing clients. Those installations require a manual upgrade or an explicitly prepared transition release before using a separate schema 3 endpoint.

Generate the signing key outside Proton and export its public key as standard PEM:

```sh
openssl genrsa -out updater-private.pem 2048
openssl pkey -in updater-private.pem -pubout -out updater-public.pem
```

Embed the contents of `updater-public.pem` in the application and pass that string to `App.update_channel`. Keep `updater-private.pem` in your signing environment; never package it with the app. Proton does not generate keys, sign release files or host an update endpoint. OS signing/notarization and updater signature verification serve different checks; configuring one does not configure the other.

## Process control and metrics

Application process control determines which instance owns the runtime and how later launches reach it. It is separate from window visibility and from the task metrics exposed by Chromium.

**Single-instance ownership**

`App.single_instance()` uses the application identity to select one owning process. Later instances forward URL, document or reopen activation and return after the primary loop accepts it. Acceptance does not wait for asynchronous launch handlers to complete. Forwarding has a five-second deadline; failure does not kill the primary or start another owner.

`ApplicationContext.has_single_instance_lock()` queries ownership and `release_single_instance_lock()` releases it during the run. Releasing does not terminate the process. Choose deliberately whether another process may now become the owner. Register launch-input handling for both initial and forwarded activations.

**App state versus window state**

Application focus, hide/show, active/hidden queries and readiness describe the application. A window handle controls one window. A hidden window remains alive, and an application with KeepRunning can remain alive with no windows. Always provide an explicit exit path for background applications.

`ApplicationContext.focus(steal=...)` activates the application on macOS; `steal` controls whether another foreground application may be displaced. On Windows and Linux it focuses the first visible window. The application-level `hide`, `show`, `is_active` and `is_hidden` methods are macOS-only and raise `AppControlError::UnsupportedPlatform` elsewhere. `@proton.is_ready()` reports application readiness.

CEF reports renderer termination through `on_render_process_gone`, but does not expose equivalent non-renderer child-process exit notifications. Electron's `child-process-gone` is therefore unsupported. Browser-operation mappings and other unsupported Electron equivalents are listed in the [page-control reference](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/proton/README.md#page-history-and-inserted-css).

**Dock and application badges**

These operations belong to a live `ApplicationContext`, not a window. Handle `AppControlError` for invalid arguments or native failures.

| API | macOS | Windows / Linux |
| --- | --- | --- |
| `set_badge_count(count) -> Bool` | Sets the numeric Dock badge and returns `true`; zero clears it | Returns `false`; no badge applied |
| `badge_count() -> Int32` | Returns the last count set through `set_badge_count` | Returns zero |
| `dock_set_badge(text)` / `dock_badge()` | Set/read arbitrary Dock badge text; empty text clears it | Raise `UnsupportedPlatform` |
| `dock_bounce(kind=Informational) -> Int32` | Requests Dock attention and returns a cancellation ID | Raise `UnsupportedPlatform` |
| `dock_cancel_bounce(request_id)` | Cancels the corresponding attention request | Raise `UnsupportedPlatform` |

Negative badge counts are rejected. `DockBounceType::Informational` bounces once; `Critical` continues until activation or cancellation. AppKit ignores attention requests while the app is already active. Numeric badge readback is Proton's stored count, not a query of the arbitrary text written with `dock_set_badge`. The badge APIs are separate from a window's Windows taskbar `set_overlay_icon`.

**Task metrics**

`ApplicationContext.task_metrics()` returns `AppTaskMetric` rows for Chromium tasks. A renderer and multiple workers can share a process. Task ids identify tasks; the hosting process usage in multiple rows may be identical because it belongs to the shared process. Do not sum rows into a process or application total.

CPU is zero until a sampling interval has passed; 100% represents one fully used core. Memory is -1 before measurement, not zero bytes. The fields are `process_cpu_percent` and `process_memory_bytes`. These observations do not confer ownership of a process and should not be used to kill helpers independently of Proton's lifecycle.

## API references

- [Application API](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/proton/pkg.generated.mbti)
- [Extension API](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/extensions/pkg.generated.mbti)
- [Typed contracts](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/contract/pkg.generated.mbti)
- [Frontend client](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/client/pkg.generated.mbti)
- [Rabbita integration](https://github.com/moonbit-community/proton/blob/6c7c6810b492ffdc57b0908fc926d67db6656eef/rabbita/pkg.generated.mbti)
