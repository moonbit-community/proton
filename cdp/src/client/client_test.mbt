///|
test "connection errors expose stable diagnostics" {
  let timeout = @client.CdpConnectionError::ConnectionTimeout(
    "ws://127.0.0.1:9222/devtools/browser/id", 250,
  )
  inspect(timeout.kind(), content="connection_timeout")
  inspect(
    timeout.web_socket_url(),
    content="ws://127.0.0.1:9222/devtools/browser/id",
  )
  guard timeout.timeout_ms() is Some(250) else { fail("expected timeout ms") }
  assert_true(timeout.reason() is None)
  inspect(timeout.path(), content="connection.websocket.timeout")
  inspect(
    timeout.message(),
    content="timed out after 250ms connecting to ws://127.0.0.1:9222/devtools/browser/id",
  )
  let diagnostic = timeout.diagnostic()
  inspect(diagnostic.kind, content="connection_timeout")
  inspect(diagnostic.path, content="connection.websocket.timeout")

  let handshake = @client.CdpConnectionError::WebSocketHandshakeFailed(
    "ws://127.0.0.1:9222/devtools/browser/id", "HTTP 404",
  )
  inspect(handshake.kind(), content="websocket_handshake_failed")
  assert_true(handshake.timeout_ms() is None)
  guard handshake.reason() is Some("HTTP 404") else {
    fail("expected handshake reason")
  }
  inspect(handshake.path(), content="connection.websocket.handshake")
  inspect(
    handshake.message(),
    content="websocket handshake failed for ws://127.0.0.1:9222/devtools/browser/id: HTTP 404",
  )
}
