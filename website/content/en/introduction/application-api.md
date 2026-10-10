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

For the complete set of methods, overloads, typed errors and defaults, use the [versioned API index](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/). This reference describes when to use each entry point, which object owns its state, and how it behaves during startup, cancellation and shutdown.

## Application lifecycle

`App` configures an application before startup. It is created through the root Proton facade and executed through the MoonBit async runtime. Proton installs its native event-loop integration during initialization; application code does not install or poll a separate UI loop.

**Entry sources**

| Constructor | Entry |
| --- | --- |
| `html(title, html, ...)` | Inline HTML document |
| `url(title, url, ...)` | URL |
| `file(title, path, ...)` | Local HTML file |
| `asset(title, path, ...)` | Managed application asset entry |

Each returns an `App` builder. Shared options include width, height, debug mode and resizability. `entry_html`, `entry_url`, `entry_file` and `entry_asset` configure the entry on an existing builder.

**Identity**

`@proton.load_config()` returns the complete typed `AppConfig` and reports loading errors immediately. Read `identifier`, `backend`, `frontend`, and `package_config` directly from this value. Install it with `app.config(config)`, which is mutually exclusive with `app.identifier(...)`. The identifier is stable application identity, distinct from the window title, product name, and version.

`app_path()`, `resource_dir()` and `is_packaged()` describe the execution environment. Development paths and packaged resources have different locations; frontend URLs are not backend filesystem paths.

**Hooks and owned state**

| Hook | Meaning |
| --- | --- |
| `app_lifecycle(on_start, on_shutdown)` | Application-level state; the start result is passed to shutdown |
| `window_lifecycle(on_ready, on_close)` | Per-window state; the ready result is passed to close |
| `on_window_close_request` | Async allow/deny decision before window closure |

Application and window contexts expose task groups and window management. Window contexts additionally expose their handle and event emitter. A window's state must not outlive the resources it refers to.

**Running the application**

Calling `run()` starts the configured application and awaits its lifecycle. It is async and raises `AppRunError` on failure. `run_or_abort()` instead reports a failure and aborts. Startup, task ownership and exit behavior are described below.

**Startup order**

Startup validates configuration, resolves identity and paths, initializes logging, and acquires the single-instance lock when configured. A secondary instance that forwards its activation returns without creating an application runtime.

For the primary instance, session creation precedes application start hooks. Successful start hooks establish the application state. Proton then opens declared startup windows that were not already opened by a start hook, waits for the required bridge initialization, and activates the initial windows through their ready hooks. Application readiness follows successful initial activation; configuring a window or receiving a native creation event does not establish readiness.

A start hook may await `context.windows().open(id)`. A committed exit stops startup. A denied quit request leaves the application running; requesting quit is not itself a committed exit.

**Task and cleanup ownership**

Use application task groups for work that belongs to the application, and window task groups for work that belongs to a window. Their scopes are canceled and drained on shutdown; detached work outside these scopes is not made lifecycle-safe by holding a window handle.

Each lifecycle hook that successfully returns state installs its paired cleanup hook. A hook that fails before returning has not produced state to pass to its paired cleanup; previously established scopes still clean up. Cleanup hooks run under cancellation protection. Reported cleanup failures can accompany the original failure in `AppRunError`, rather than replacing it.

Ready/close hooks own per-window state; creation and browser event callbacks report observations. A renderer can navigate or crash while its native window remains alive. Page tasks and subscriptions must therefore also respect page lifetime, as described in [commands](#commands) and [events](#events).

**Quit decisions and forced exit**

| Operation | Contract |
| --- | --- |
| `context.quit(exit_code=0)` | Requests orderly shutdown; cancelable |
| `context.exit(exit_code=0)` | Forces shutdown and process termination, including status zero |
| `handle.close()` | Requests closing that window; subject to its close interceptor |

The default `LastWindowClosedPolicy::Quit` requests shutdown after the last window closes; `KeepRunning` keeps the application running until an explicit quit or exit. Browser and child-view teardown must finish before normal runtime shutdown completes.

An orderly quit runs `on_before_quit`, closes windows through their close decisions, then runs `on_will_quit` after windows close. `ApplicationQuitDecision::Prevent` cancels the quit; a denied window close also cancels the request. Cancellation does not recreate windows that have already closed. `on_quit` observes the final exit code before runtime teardown and is not a veto point.

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

Request concurrency has no global fixed admission limit in 0.3.4. Applications still need to bound expensive work according to their own resource and ordering requirements; the bridge does not serialize unrelated business operations into a transaction.

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

`proton_rabbita.subscribe` integrates subscription ownership into Rabbita. Its options include a subscription key, retry count, ready command and client override; full signatures are in the [Rabbita API](https://mooncakes.io/docs/moonbit-community/proton_rabbita@0.3.4/).

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

Window declarations belong to `App`; operations on a running window belong to `WindowHandle`. Browser navigation and developer tools belong to `BrowserHandle`, obtained through `WindowHandle.browser()`.

**Identity and declaration**

The primary window ID is `main`. `App.add_window(id, title, entry, ...)` declares secondary windows; their IDs must be nonempty, unique and different from `main`. Titles are display text and do not identify windows.

Secondary windows open at startup by default. `open_on_start=false` defers opening until `WindowManager.open(id)`. `ApplicationContext.windows()` and `WindowContext.windows()` expose the manager. All windows belong to one application runtime.

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

`App.on_window_close_request` registers an async callback that receives the window handle and returns `WindowCloseDecision::Allow` or `Deny`. `window_lifecycle.on_close` is cleanup after closure; it is not a veto hook. The default last-window policy is `Quit`. `KeepRunning` leaves the application running with no open windows and requires an explicit exit path. See [application lifecycle](#application-lifecycle).

**Child browser views**

`App.with_view` declares a view on the main window; `WindowHandle.add_view` creates one dynamically and returns `ViewHandle`. A view is a child browser hosted inside a window, not a second top-level window. Its bounds use a top-left origin; visibility and z-order are independent of the main page. `remove_view` removes a child. Closing the parent must also complete child-browser teardown.

**Browser and view boundaries**

The main page belongs to `WindowHandle.browser()`. Child contents belong to `ViewHandle`; child navigation and removal do not navigate or close the main page. Both are represented by `WebContentsHandle` in application-level creation and renderer-termination callbacks.

`on_render_process_gone` covers both main pages and child views without requiring an extra `on_view_event` subscription. Renderer termination invalidates page work; it is not a normal window close. Decide whether to reload or present recovery UI based on the reported details, and recreate page subscriptions after navigation.

A view declaration sets initial geometry; it does not provide automatic layout. Update its bounds when the parent content layout changes.

**Platform behavior**

`WindowThemePreference` controls a window's theme; `system_appearance()` reports system appearance. These are separate concerns. Titlebar styles and native controls differ by platform. Traffic-light positioning applies to macOS; the frontend layout must account for native controls when using an overlay titlebar.

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

**Availability and errors**

A missing capability leaves its route unavailable. An installed extension can still reject a request because of scope, invalid arguments, a platform limitation or an operating-system failure. These failures are reported through the command bridge; installation does not imply that every native operation will succeed.

Capability-specific scope types are documented in the extension API; platform coverage is summarized below.

**Platform differences and selection**

These are key boundaries of implemented 0.3.4 capabilities, not a promise of availability without desktop services:

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

See the [extension API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.3.4/) for the complete inventory and scope types. Check target grants, OS permission and platform backend support independently.

## Browser sessions

A browser session contains cookies, cache, authentication state and web storage. Obtain its handle from `window.browser().session()`. A handle is reached through a browser, but clearing shared session data is not a private operation on that one page.

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

Operations can fail when the owning browser/window is no longer usable. Await cookie reads inside a live lifecycle scope. A clearing operation does not erase application-owned files or implement an application logout protocol; invalidate backend credentials and UI state separately.

Full attributes and `StorageDataKind` variants are in the [API reference](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/).

## Application updates

Application updates replace the distributed application, not the development CLI or Mooncakes dependencies. Configure `App.update_channel(endpoint, public_keys, check_on_launch?, freshness_days?)` before running the app.

**Channel and checks**

The endpoint must use HTTPS and there must be at least one trusted RSA public key. Automatic checking defaults to enabled; manifest freshness defaults to 30 days and must be positive. Keys use the format validated by [`updater public-key`](../command-line-interface/commands.md#updater-public-key).

The automatic check runs after successful startup and reports failures through logging without making startup fail. For explicit checks, use `ApplicationContext.check_for_update()` and handle its result and errors. `NotConfigured` is distinct from `UpToDate`; a context used after its application ends no longer has an active channel.

An offered `PendingUpdate` has passed manifest trust, freshness and revision checks. It exposes version, revision, size and optional notes URL, but the artifact has not yet been downloaded.

**Download and installation**

`PendingUpdate.download()` writes the artifact into a private stage and verifies its size, digest and signature. It does not replace application files or exit on any platform. Repeated downloads of the same prepared revision are a no-op.

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

Package a stable application identifier with a monotonically increasing revision. The updater metadata options in [CLI package](../command-line-interface/commands.md#package) describe the artifact location, publication instant and revision. `updater public-key` only formats a public key; it does not generate keys, sign an update manifest or host an endpoint. OS signing/notarization and updater signature verification serve different checks; configuring one does not configure the other.

## Process control and metrics

Application process control determines which instance owns the runtime and how later launches reach it. It is separate from window visibility and from the task metrics exposed by Chromium.

**Single-instance ownership**

`App.single_instance()` uses the application identity to select one owning process. Later instances forward URL, document or reopen activation and return after the primary loop accepts it. Acceptance does not wait for asynchronous launch handlers to complete. Forwarding has a five-second deadline; failure does not kill the primary or start another owner.

`ApplicationContext.has_single_instance_lock()` queries ownership and `release_single_instance_lock()` releases it during the run. Releasing does not terminate the process. Choose deliberately whether another process may now become the owner. Register launch-input handling for both initial and forwarded activations.

**App state versus window state**

Application focus, hide/show, active/hidden queries and readiness describe the application. A window handle controls one window. A hidden window remains alive, and an application with KeepRunning can remain alive with no windows. Always provide an explicit exit path for background applications.

**Task metrics**

`ApplicationContext.task_metrics()` returns `AppTaskMetric` rows for Chromium tasks. A renderer and multiple workers can share a process. Task ids identify tasks; the hosting process usage in multiple rows may be identical because it belongs to the shared process. Do not sum rows into a process or application total.

CPU is zero until a sampling interval has passed; 100% represents one fully used core. Memory is -1 before measurement, not zero bytes. The fields are `process_cpu_percent` and `process_memory_bytes`. These observations do not confer ownership of a process and should not be used to kill helpers independently of Proton's lifecycle.

## API references

- [Application API](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/)
- [Extension API](https://mooncakes.io/docs/moonbit-community/proton_ext@0.3.4/)
- [Typed contracts](https://mooncakes.io/docs/moonbit-community/proton_contract@0.3.4/)
- [Frontend client](https://mooncakes.io/docs/moonbit-community/proton_client@0.3.4/)
- [Rabbita integration](https://mooncakes.io/docs/moonbit-community/proton_rabbita@0.3.4/)
