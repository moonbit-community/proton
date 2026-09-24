# proton/ipc

`moonbit-community/proton/ipc` defines transport-neutral protocol types for Proton.

It does not know about WebView, WebSocket, process launch, or extension code.
The current root facade uses these types with Proton's private source-built
native bridge.

Protocol version 2 preserves command failures as an `IpcCommandError` object in
`IpcOpResponse.body`: `code`, `message`, and optional `detail`. Successful bodies
are unchanged. Version 1 envelopes, whose failure bodies were strings, are
rejected by version validation. Direct users of `IpcOpResponse::err` must pass
an `IpcCommandError` instead of a string; the frontend invocation interface is
unchanged.
