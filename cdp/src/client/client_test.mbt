///|
async fn[T, E : Error] try_result_client_client_test(
  f : async () -> T raise E,
) -> Result[T, E] {
  try f() catch {
    e => Err(e)
  } noraise {
    value => Ok(value)
  }
}

///|
async test "cdp client sends command and waits for matching response" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      let ws = @websocket.from_http_server(request, conn)
      defer ws.close()
      let text = ws.recv().read_all().text()
      assert_true(text.contains("\"method\":\"Runtime.evaluate\""))
      assert_true(text.contains("\"id\":1"))
      ws.send_text(
        "{\"method\":\"Runtime.executionContextCreated\",\"params\":{}}",
      )
      ws.send_text("{\"id\":1,\"result\":{\"ok\":true}}")
    }
    let client = @client.CdpClient::connect("ws://localhost:\{addr.port()}")
    defer client.close()
    let response = client.send_command("Runtime.evaluate", params={
      "expression": "1+1",
    })
    inspect(response.id, content="1")
    guard client.last_cdp_request() is Some(request) else {
      fail("expected last CDP request")
    }
    inspect(request.method_name, content="Runtime.evaluate")
    guard client.last_cdp_response() is Some(last_response) else {
      fail("expected last CDP response")
    }
    inspect(last_response.id, content="1")
    guard client.last_cdp_event() is Some(event) else {
      fail("expected last CDP event")
    }
    inspect(event.method_name, content="Runtime.executionContextCreated")
    guard response.result is Some({ "ok": true, .. }) else {
      fail("expected result")
    }
  }
}

///|
async test "cdp client sends generated command messages and decodes typed results" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      let ws = @websocket.from_http_server(request, conn)
      defer ws.close()
      let first = ws.recv().read_all().text()
      assert_true(first.contains("\"id\":7"))
      assert_true(first.contains("\"method\":\"Runtime.evaluate\""))
      assert_true(first.contains("\"sessionId\":\"session-1\""))
      ws.send_text(
        "{\"id\":7,\"result\":{\"result\":{\"type\":\"number\",\"value\":2},\"exceptionDetails\":null},\"sessionId\":\"session-1\"}",
      )
      let second = ws.recv().read_all().text()
      assert_true(second.contains("\"id\":8"))
      assert_true(second.contains("\"method\":\"Runtime.enable\""))
      ws.send_text("{\"id\":8,\"result\":{}}")
    }
    let client = @client.CdpClient::connect("ws://localhost:\{addr.port()}")
    defer client.close()
    let params : @typed.RuntimeEvaluateParams = {
      expression: "1 + 1",
      object_group: None,
      include_command_line_api: None,
      silent: None,
      context_id: None,
      return_by_value: Some(true),
      generate_preview: None,
      user_gesture: None,
      await_promise: None,
      throw_on_side_effect: None,
      timeout: None,
      disable_breaks: None,
      repl_mode: None,
      allow_unsafe_eval_blocked_by_csp: None,
      unique_context_id: None,
      serialization_options: None,
    }
    let command = @typed.runtime_evaluate_command(
      id=7,
      params,
      session_id="session-1",
    )
    let response = client.send_cdp_message(command)
    let result = @typed.RuntimeEvaluateResult::from_json(
      @client.cdp_response_result_json(response),
    )
    inspect(result.result.type_, content="number")
    let next = client.send_command("Runtime.enable")
    inspect(next.id, content="8")
  }
}

///|
async test "cdp client sends schema commands and validates schema responses" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      let ws = @websocket.from_http_server(request, conn)
      defer ws.close()
      let first = ws.recv().read_all().text()
      assert_true(first.contains("\"id\":1"))
      assert_true(first.contains("\"method\":\"Page.navigate\""))
      ws.send_text(
        "{\"id\":1,\"result\":{\"frameId\":\"frame-1\",\"loaderId\":null,\"isDownload\":false},\"sessionId\":\"session-1\"}",
      )
      let second = ws.recv().read_all().text()
      assert_true(second.contains("\"id\":2"))
      assert_true(second.contains("\"method\":\"Page.navigate\""))
      ws.send_text("{\"id\":2,\"result\":{},\"sessionId\":\"session-1\"}")
    }
    let client = @client.CdpClient::connect("ws://localhost:\{addr.port()}")
    defer client.close()
    let response = client.send_schema_command(
      "Page.navigate",
      params={ "url": "https://example.com/" },
      session_id="session-1",
    )
    let result = @typed.PageNavigateResult::from_json(
      @client.cdp_response_result_json(response),
    )
    inspect(result.frame_id.value, content="frame-1")
    let invalid : Result[@protocol.CdpResponseMessage, Error] = try_result_client_client_test(() => {
        client.send_schema_command(
          "Page.navigate",
          params={ "url": "https://example.com/" },
          session_id="session-1",
        )
      },
    )
    guard invalid
      is Err(
        @protocol.ProtocolSchemaError::MissingReturn("Page.navigate", "frameId")
      ) else {
      fail("expected missing frameId")
    }
  }
}

///|
async test "cdp client exposes raw event buffer subscriptions and drain" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      let ws = @websocket.from_http_server(request, conn)
      defer ws.close()
      ws.send_text(
        "{\"method\":\"Runtime.consoleAPICalled\",\"sessionId\":\"session-1\",\"params\":{\"type\":\"log\",\"args\":[{\"type\":\"string\",\"value\":\"hello\"}]}}",
      )
      ws.send_text(
        "{\"method\":\"Page.loadEventFired\",\"sessionId\":\"session-2\",\"params\":{\"timestamp\":1}}",
      )
    }
    let client = @client.CdpClient::connect("ws://localhost:\{addr.port()}")
    defer client.close()
    let seen : Array[String] = []
    let handler_id = client.on_cdp_event(
      method_name="Runtime.consoleAPICalled",
      session_id="session-1",
      fn(event) { seen.push(event.method_name) },
    )
    let event = client.recv_cdp_event(
      method_name="Runtime.consoleAPICalled",
      session_id="session-1",
    )
    inspect(event.method_name, content="Runtime.consoleAPICalled")
    json_inspect(seen, content=["Runtime.consoleAPICalled"])
    assert_true(client.remove_cdp_event_handler(handler_id))
    let load = client.recv_cdp_event(method_name="Page.loadEventFired")
    assert_true(load.session_id == Some("session-2"))
    client.clear_cdp_events()
    inspect(client.cdp_events().length(), content="0")
  }
}

///|
async test "cdp client tracks target attached and detached events" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      let ws = @websocket.from_http_server(request, conn)
      defer ws.close()
      ignore(ws.recv().read_all())
      ws.send_text(
        "{\"method\":\"Target.attachedToTarget\",\"params\":{\"sessionId\":\"session-1\",\"targetInfo\":{\"targetId\":\"target-1\",\"type\":\"page\",\"title\":\"Example\",\"url\":\"https://example.com/\",\"attached\":true,\"browserContextId\":\"context-1\"},\"waitingForDebugger\":true}}",
      )
      ws.send_text("{\"id\":1,\"result\":{\"sessionId\":\"session-1\"}}")
      ignore(ws.recv().read_all())
      ws.send_text(
        "{\"method\":\"Target.detachedFromTarget\",\"params\":{\"sessionId\":\"session-1\",\"targetId\":\"target-1\"}}",
      )
      ws.send_text("{\"id\":2,\"result\":{}}")
    }
    let client = @client.CdpClient::connect("ws://localhost:\{addr.port()}")
    defer client.close()
    let session_id = client.attach_to_target("target-1")
    inspect(session_id, content="session-1")
    guard client.attached_target("session-1") is Some(attached) else {
      fail("expected attached target")
    }
    inspect(attached.target_id, content="target-1")
    ignore(client.send_command("Runtime.enable", session_id="session-1"))
    assert_true(client.attached_target("session-1") is None)
  }
}

///|
async test "connection helpers open direct websocket targets" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      for _ in 0..<6 {
        let (conn, _) = server.accept()
        defer conn.close()
        let request = conn.read_request()
        let ws = @websocket.from_http_server(request, conn)
        ws.close()
      }
    }
    let browser_url = "ws://127.0.0.1:\{addr.port()}/devtools/browser/id"
    let page_url = "ws://127.0.0.1:\{addr.port()}/devtools/page/page-1"

    let direct = @client.connect_cdp_target(WebSocket(browser_url))
    direct.close()
    let direct_timeout = @client.connect_cdp_target_with_timeout(
      WebSocket(browser_url),
      timeout_ms=1000,
    )
    direct_timeout.close()
    let browser = @client.connect_cdp_browser_target(WebSocket(browser_url))
    browser.close()
    let browser_timeout = @client.connect_cdp_browser_target_with_timeout(
      WebSocket(browser_url),
      timeout_ms=1000,
    )
    browser_timeout.close()
    let page = @client.connect_cdp_page_target(WebSocket(page_url))
    page.close()
    let page_timeout = @client.connect_cdp_page_target_with_timeout(
      WebSocket(page_url),
      timeout_ms=1000,
    )
    page_timeout.close()
  }
}

///|
async test "connect_with_timeout reports invalid websocket endpoints" {
  let result : Result[@client.CdpClient, Error] = try_result_client_client_test(() => {
      @client.CdpClient::connect_with_timeout(
        "ws://127.0.0.1:1/devtools/browser/id",
        timeout_ms=50,
      )
    },
  )
  match result {
    Err(@client.CdpConnectionError::WebSocketHandshakeFailed(_, _))
    | Err(@client.CdpConnectionError::ConnectionTimeout(_, _)) => ()
    Ok(client) => {
      client.close()
      fail("expected websocket connection failure")
    }
    Err(_) => fail("expected structured connection error")
  }
}

///|
async test "cdp client sends remote-schema validated commands" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      let ws = @websocket.from_http_server(request, conn)
      defer ws.close()
      let text = ws.recv().read_all().text()
      assert_true(text.contains("\"method\":\"Runtime.evaluate\""))
      assert_true(text.contains("\"expression\":\"1 + 1\""))
      ws.send_text(
        "{\"id\":1,\"result\":{\"result\":{\"type\":\"number\",\"value\":2},\"exceptionDetails\":null}}",
      )
    }
    let client = @client.CdpClient::connect("ws://127.0.0.1:\{addr.port()}")
    defer client.close()
    let remote_schema : Json = {
      "domains": [{ "domain": "Runtime", "commands": [{ "name": "evaluate" }] }],
    }
    let response = client.send_remote_schema_command(
      remote_schema,
      "Runtime.evaluate",
      params={ "expression": "1 + 1" },
    )
    inspect(response.id, content="1")
    guard response.result is Some({ "result": { "type": "number", .. }, .. }) else {
      fail("expected Runtime.evaluate result")
    }
  }
}

///|
async test "cdp client records command failures" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      let ws = @websocket.from_http_server(request, conn)
      defer ws.close()
      ignore(ws.recv().read_all())
      ws.send_text(
        "{\"id\":1,\"error\":{\"code\":-32000,\"message\":\"failed\",\"data\":{\"reason\":\"test\"}}}",
      )
    }
    let client = @client.CdpClient::connect("ws://127.0.0.1:\{addr.port()}")
    defer client.close()
    let response = client.send_command("Runtime.evaluate", params={
      "expression": "throw new Error()",
    })
    guard response.error is Some(error) else {
      fail("expected CDP error response")
    }
    inspect(error.code, content="-32000")
    guard client.last_command_failure() is Some(failure) else {
      fail("expected last command failure")
    }
    inspect(failure.method_name, content="Runtime.evaluate")
    inspect(failure.message, content="failed")
  }
}

///|
async test "recv_cdp_response times out and clears inflight state" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      let ws = @websocket.from_http_server(request, conn)
      defer ws.close()
      ignore(ws.recv().read_all())
      @async.sleep(100)
    }
    let client = @client.CdpClient::connect("ws://127.0.0.1:\{addr.port()}")
    defer client.close()
    let id = client.send_cdp_command("Runtime.evaluate", params={
      "expression": "1",
    })
    let result : Result[@protocol.CdpResponseMessage, Error] = try_result_client_client_test(() => {
        client.recv_cdp_response(id, timeout_ms=1)
      },
    )
    guard result is Err(@client.BrowserError::WaitTimeout("cdp response 1")) else {
      fail("expected response timeout")
    }
  }
}

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
