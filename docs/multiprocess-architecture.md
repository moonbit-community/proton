# Lepus Multiprocess Runtime

This design moves business ops out of the webview process and into a separate
MoonBit native process.

## Process Model

- **Webview process** owns native windows, page loading, injected JavaScript, and
  the `window.__MoonBit__` bridge.
- **MBT process** owns application commands, stateful business logic, extension
  command handlers, and `moonbitlang/async`.
- **IPC transport** carries JSON frames between the two processes. The protocol
  is transport-neutral so the current MoonBit-managed file IPC transport,
  stdio, named pipes, Unix domain sockets, and later platform-specific app
  service transports can share the same runtime contracts.

This matches the Tauri/Electron split at a high level: the renderer/webview is
not where privileged MoonBit application code runs.

## Protocol

Every op call from JavaScript becomes one `IpcOpRequest`:

```json
{
  "version": 1,
  "id": "binding-request-id",
  "name": "ext:fs/readFile",
  "payload": {}
}
```

The MBT process responds with one `IpcOpResponse`:

```json
{
  "version": 1,
  "id": "binding-request-id",
  "status": 0,
  "body": {}
}
```

`status == 0` means success. Non-zero status means `body` is a JSON string error
message that can be forwarded directly to `webview_return`.

Events travel from the MBT process to the webview process as `IpcExtensionEvent`
frames and are emitted into `window.__MoonBit__.events`.

## Implementation Stages

1. Add protocol types plus an MBT-side `MbtProcessHost` that can register sync
   and async ops.
2. Add a webview-side `IpcOpTransport` and `install_ipc_op_runtime(...)` that
   forwards JS op invocations to any transport implementation.
3. Add a MoonBit child-process transport as the default local development
   transport.
4. Teach `runtime` and `app` to manage an app-wide backend transport shared by
   every current and future window.
5. Teach `app` tooling to generate two explicit entrypoints:
   - webview executable: window + IPC bridge
   - mbt executable: command host + async runtime

## Current API Sketch

The app executable installs the JavaScript bridge and forwards ops to an app
service:

```moonbit
fn main {
  let service = @app.AppServiceConfig::new(
    "my_app_service.exe",
    ["app:ping", "app:sleep"],
  )
  match @app.create_app_with_service(manifest, registry, service) {
    Ok(app) => app.run()
    Err(error) => abort(error)
  }
}
```

The service executable runs normal MoonBit code and async handlers:

```moonbit
async fn main {
  let host = @core.AppServiceHost::new()
  host.op("app:ping", fn(_payload : PingPayload) {
    PingReply::{ ok: true }
  })
  host.op_async_result("app:sleep", async fn(payload : SleepPayload) {
    @async.sleep(payload.ms)
    Ok(SleepReply::{ done: true })
  })
  host.run()
}
```

The default app-side transport starts the service with a local file IPC
directory passed through the process environment. `AppServiceHost::run()` keeps
the service entrypoint stable while the runtime chooses the concrete transport.

This is intentionally explicit: the application links the service it wants,
while the runtime owns the transport and lifecycle details.

At the app layer, callers can install the same service across all windows. Apps
can either install the service on a runtime app directly, or use the high-level
manifest composition helper:

```moonbit
fn main {
  let service = @app.AppServiceConfig::new(
    "my_app_service.exe",
    ["app:ping", "app:sleep"],
  )
  match @app.create_app_with_service(manifest, registry, service) {
    Ok(app) => app.run()
    Err(error) => abort(error)
  }
}
```

```moonbit
fn main {
  let app = @runtime.App::new(config)
  app.install_service("my_app_service.exe", ["app:ping"])
  app.run()
}
```

## Open Decisions

- Default transport per platform: MoonBit file IPC is enough for local
  development without project-owned native C; named pipes or Unix domain sockets
  are better future options for high-throughput bidirectional event streams.
- Packaging contract: callers can provide a backend executable path, or tooling
  can generate both entrypoints.
- Which built-in extensions live in the webview process versus MBT process.
  Extensions that require direct native window handles probably stay webview-side;
  file, path, shell, and most business commands can move MBT-side.
