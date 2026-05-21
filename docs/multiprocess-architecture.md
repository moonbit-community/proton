# Lepus Multiprocess Runtime

This design moves business ops out of the webview process and into a separate
MoonBit native process.

## Process Model

- **Webview process** owns native windows, page loading, injected JavaScript, and
  the `window.__MoonBit__` bridge.
- **MBT process** owns application commands, stateful business logic, extension
  command handlers, and `moonbitlang/async`.
- **IPC transport** carries JSON frames between the two processes. The protocol
  is transport-neutral so stdio, named pipes, Unix domain sockets, and later
  platform-specific app service transports can share the same runtime contracts.

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
3. Add a native stdio child-process transport as the default local development
   transport.
4. Teach `runtime` and `app` to manage an app-wide backend transport shared by
   every current and future window.
5. Teach `app` tooling to generate two explicit entrypoints:
   - webview executable: window + IPC bridge
   - mbt executable: command host + async runtime

## Current API Sketch

The webview executable installs the JavaScript bridge and forwards ops to a
backend child process:

```moonbit
fn main {
  let webview = @webview.Webview::new(debug=1)
  let transport = @core.IpcOpTransport::stdio_process(
    "my_app_backend.exe",
    args=[],
  )
  @core.install_ipc_op_runtime(webview, transport, ["app:ping"])
  webview.set_html("<html></html>")
  webview.run()
}
```

The backend executable runs normal MoonBit code and async handlers:

```moonbit
async fn main {
  let host = @core.MbtProcessHost::new()
  host.op("app:ping", fn(_payload : PingPayload) {
    PingReply::{ ok: true }
  })
  host.op_async_result("app:sleep", async fn(payload : SleepPayload) {
    @async.sleep(payload.ms)
    Ok(SleepReply::{ done: true })
  })
  host.run_stdio()
}
```

This is intentionally explicit: the application links and launches the backend
it wants, while the webview side stays a small shell.

At the app layer, callers can install the same backend across all windows. The
app owns the backend process lifetime, while each window only owns its JS
binding:

```moonbit
fn main {
  let app = @runtime.App::new(config)
  app.install_mbt_process_backend(
    "my_app_backend.exe",
    ["app:ping", "app:sleep"],
  )
  app.run()
}
```

## Open Decisions

- Default transport per platform: stdio is simplest; named pipes or Unix domain
  sockets are better for long-running bidirectional event streams.
- Packaging contract: callers can provide a backend executable path, or tooling
  can generate both entrypoints.
- Which built-in extensions live in the webview process versus MBT process.
  Extensions that require direct native window handles probably stay webview-side;
  file, path, shell, and most business commands can move MBT-side.
