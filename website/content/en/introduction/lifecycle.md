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

See [application API](https://mooncakes.io/docs/moonbit-community/proton@0.3.3/) for hook signatures and error variants.
