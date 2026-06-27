# proton/ipc/ws

`justjavac/proton/ipc/ws` provides an experimental local HTTP/WebSocket
transport over the transport-neutral `justjavac/proton/ipc` protocol.

The current app runtime route does not use this package. Ordinary apps should
start from the root `justjavac/proton` facade, which talks to the native Proton
dynamic library directly.

It owns:

- loopback WebSocket server startup
- health checks for readiness
- launch-token validation
- browser `Origin` checks
- protocol request dispatch
- extension event streaming

Use `WsIpcLaunchConfig::auto_with_token(...)` when the launcher can provide a
strong per-run token.
