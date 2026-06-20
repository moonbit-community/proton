# proton/ipc/ws

HTTP/WebSocket IPC transport for Proton.

The user process runs the local WebSocket server, exposes a health endpoint for
startup readiness, dispatches protocol requests, and can stream extension events
back over connected WebSocket clients. After the user process observes
`wait_ws_ipc_ready(...)`, it starts the framework child process. The framework
process then injects the generated JavaScript bridge into WebView and connects
back to the user process through the launch config.

The server is bound to loopback and validates browser `Origin` headers before
serving health checks or upgrading to WebSocket. Local WebView origins such as
`null`, `file://`, `localhost`, `*.localhost`, `127.0.0.1`, and `[::1]` are
accepted; ordinary remote origins are rejected before token validation. The
launch token is a per-run nonce used as an extra guard, not the only security
boundary. When a launcher can provide platform CSPRNG material, prefer
`WsIpcLaunchConfig::auto_with_token(...)`; the built-in `auto()` token exists
for pure MoonBit setups where loopback and Origin checks remain the main
boundary.
