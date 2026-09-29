# Application lifecycle

`App` configures an application before startup. It is created through the root Proton facade and executed through the MoonBit async runtime. Proton installs its native event-loop integration during initialization; application code does not install or poll a separate UI loop.

## Entry sources

| Constructor | Entry |
| --- | --- |
| `html(title, html, ...)` | Inline HTML document |
| `url(title, url, ...)` | URL |
| `file(title, path, ...)` | Local HTML file |
| `asset(title, path, ...)` | Managed application asset entry |

Each returns an `App` builder. Shared options include width, height, debug mode and resizability. `entry_html`, `entry_url`, `entry_file` and `entry_asset` configure the entry on an existing builder.

## Identity

`load_config()` loads managed application metadata, including the required identifier. An unmanaged application can set `identifier(...)` explicitly. The identifier is stable application identity; it is distinct from the window title, product display name and application version.

`app_path()`, `resource_dir()` and `is_packaged()` describe the execution environment. Development paths and packaged resources have different locations; frontend URLs are not backend filesystem paths.

## Hooks and owned state

| Hook | Meaning |
| --- | --- |
| `app_lifecycle(on_start, on_shutdown)` | Application-level state; the start result is passed to shutdown |
| `window_lifecycle(on_ready, on_close)` | Per-window state; the ready result is passed to close |
| `on_window_close_request` | Async allow/deny decision before window closure |

Application and window contexts expose task groups and window management. Window contexts additionally expose their handle and event emitter. A window's state must not outlive the resources it refers to.

## Execution and exit

`run()` is async and raises `AppRunError`. `run_or_abort()` reports failures and aborts rather than returning a typed error to the caller. The default `LastWindowClosedPolicy::Quit` initiates application shutdown after the last window closes; `KeepRunning` retains the process. `ApplicationContext.quit()` requests application shutdown.

Window disappearance is not completion of application cleanup. Browser and child-view teardown must finish before normal runtime shutdown completes. Forced process termination is not equivalent to a successful lifecycle.

See [application API](https://mooncakes.io/docs/moonbit-community/proton@0.3.4/) for hook signatures and error variants.

## Startup order

Startup validates configuration, resolves identity and paths, initializes logging, and acquires the single-instance lock when configured. A secondary instance that forwards its activation returns without creating an application runtime.

For the primary instance, session creation precedes application start hooks. Successful start hooks establish the application state. Proton then opens declared startup windows that were not already opened by a start hook, waits for the required bridge initialization, and activates the initial windows through their ready hooks. Application readiness follows successful initial activation; configuring a window or receiving a native creation event does not establish readiness.

A start hook may await `context.windows().open(id)`. A committed exit stops startup. A denied quit request leaves the application running; requesting quit is not itself a committed exit.

## Quit decisions and forced exit

| Operation | Contract |
| --- | --- |
| `context.quit(exit_code=0)` | Requests orderly shutdown; cancelable |
| `context.exit(exit_code=0)` | Forces shutdown and process termination, including status zero |
| `handle.close()` | Requests closing that window; subject to its close interceptor |

An orderly quit runs `on_before_quit`, closes windows through their close decisions, then runs `on_will_quit` after windows close. `ApplicationQuitDecision::Prevent` cancels the quit; a denied window close also cancels the request. Cancellation does not recreate windows that have already closed. `on_quit` observes the final exit code before runtime teardown and is not a veto point.

Forced exit bypasses cancelable decisions, including an already pending decision, but still performs the final quit notification and runtime cleanup. It is not equivalent to externally killing the process. Scheduled relaunches are started after cleanup and before process termination.

On successful ordinary zero-status quit, `App.run()` returns. A successful nonzero quit terminates with that status; forced exit terminates even for zero. Code following `run()` must not be the only place for required shutdown cleanup.

## Task and cleanup ownership

Use application task groups for work that belongs to the application, and window task groups for work that belongs to a window. Their scopes are canceled and drained on shutdown; detached work outside these scopes is not made lifecycle-safe by holding a window handle.

Each lifecycle hook that successfully returns state installs its paired cleanup hook. A hook that fails before returning has not produced state to pass to its paired cleanup; previously established scopes still clean up. Cleanup hooks run under cancellation protection. Reported cleanup failures can accompany the original failure in `AppRunError`, rather than replacing it.

Ready/close hooks own per-window state; creation and browser event callbacks report observations. A renderer can navigate or crash while its native window remains alive. Page tasks and subscriptions must therefore also respect page lifetime, as described in [commands](commands-events.md) and [events](events.md).
