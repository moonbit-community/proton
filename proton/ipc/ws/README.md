# proton/ipc/ws

`justjavac/proton/ipc/ws` provides the local HTTP/WebSocket transport used
between the user process and the framework process.

It owns:

- loopback WebSocket server startup
- health checks for readiness
- launch-token validation
- browser `Origin` checks
- protocol request dispatch
- extension event streaming

Use `WsIpcLaunchConfig::auto_with_token(...)` when the launcher can provide a
strong per-run token.
