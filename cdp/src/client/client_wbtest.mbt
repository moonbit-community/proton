///|
fn[T, E : Error] try_result_client_client_wbtest(
  f : () -> T raise E,
) -> Result[T, E] {
  try f() catch {
    e => Err(e)
  } noraise {
    value => Ok(value)
  }
}

///|
async fn[T, E : Error] try_result_client_client_wbtest_async(
  f : async () -> T raise E,
) -> Result[T, E] {
  try f() catch {
    e => Err(e)
  } noraise {
    value => Ok(value)
  }
}

///|
async test "close clears in-flight command state" {
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
      ignore(ws.recv())
      ignore(ws.recv())
      ws.send_text("{\"id\":1,\"result\":{\"ok\":true}}")
      ws.send_text("{\"id\":2,\"result\":{\"ok\":true}}")
      try ws.recv() catch {
        _ => ()
      } noraise {
        _ => ()
      }
    }
    let client = CdpClient::connect("ws://127.0.0.1:\{addr.port()}")
    let first = client.send_cdp_command("Runtime.evaluate")
    let second = client.send_cdp_command("Page.enable")
    inspect(first, content="1")
    inspect(second, content="2")
    ignore(client.recv_cdp_response(second))
    inspect(client.pending_responses.length(), content="1")
    inspect(client.command_contexts.length(), content="1")
    client.close()
    inspect(client.pending_responses.length(), content="0")
    inspect(client.command_contexts.length(), content="0")
  }
}

///|
async test "client state helpers cover buffered responses and events" {
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
      try ws.recv() catch {
        _ => ()
      } noraise {
        _ => ()
      }
    }
    let client = CdpClient::connect("ws://127.0.0.1:\{addr.port()}")
    defer client.close()

    client.reserve_cdp_command_id(5)
    inspect(client.next_id, content="6")
    client.command_contexts[5] = {
      method_name: "Runtime.evaluate",
      session_id: None,
    }
    let duplicate : Result[Unit, Error] = try_result_client_client_wbtest(() => {
      client.reserve_cdp_command_id(5)
    })
    guard duplicate is Err(BrowserError::InvalidField("id")) else {
      fail("expected duplicate id rejection")
    }
    let invalid : Result[Unit, Error] = try_result_client_client_wbtest(() => {
      client.reserve_cdp_command_id(0)
    })
    guard invalid is Err(BrowserError::InvalidField("id")) else {
      fail("expected invalid id rejection")
    }

    let response : @protocol.CdpResponseMessage = {
      id: 5,
      result: Some({ "ok": true }),
      error: None,
      session_id: None,
    }
    client.pending_responses[5] = response
    let received = client.recv_response(5)
    inspect(received.id, content="5")
    assert_true(client.pending_responses.get(5) is None)

    let error_response : @protocol.CdpResponseMessage = {
      id: 99,
      result: None,
      error: Some({ code: -32000, message: "failed", data: None }),
      session_id: Some("session-1"),
    }
    ignore(client.finish_response(error_response))
    guard client.last_command_failure() is Some(failure) else {
      fail("expected command failure")
    }
    inspect(failure.method_name, content="")
    guard failure.session_id is Some("session-1") else {
      fail("expected response session fallback")
    }

    client.record_cdp_event({
      method_name: "Target.attachedToTarget",
      params: Some({
        "sessionId": "",
        "targetInfo": {
          "targetId": "empty-session",
          "type": "page",
          "title": "Empty",
          "url": "about:blank",
        },
      }),
      session_id: None,
    })
    inspect(client.attached_targets().length(), content="0")

    let attached_event : @protocol.CdpEventMessage = {
      method_name: "Target.attachedToTarget",
      params: Some({
        "sessionId": "session-1",
        "targetInfo": {
          "targetId": "target-1",
          "type": "page",
          "title": "Example",
          "url": "https://example.com/",
          "attached": false,
        },
        "waitingForDebugger": false,
      }),
      session_id: None,
    }
    client.record_cdp_event(attached_event)
    inspect(client.attached_targets().length(), content="1")
    guard client.attached_target("session-1") is Some(target) else {
      fail("expected attached target")
    }
    inspect(target.target_id, content="target-1")
    inspect(target.attached, content="false")
    inspect(target.waiting_for_debugger, content="false")

    let matching_events = client.cdp_events(
      method_name="Target.attachedToTarget",
    )
    inspect(matching_events.length(), content="2")
    let all_events = client.cdp_events()
    assert_true(all_events.length() >= 2)
    assert_true(cdp_event_matches(attached_event))

    let called : Array[String] = []
    let keep_id = client.on_cdp_event(event => called.push(event.method_name))
    let remove_id = client.on_cdp_event(
      method_name="Runtime.consoleAPICalled",
      event => called.push(event.method_name),
    )
    assert_true(client.remove_cdp_event_handler(remove_id))
    assert_true(!client.remove_cdp_event_handler(9999))
    inspect(client.cdp_event_handlers.length(), content="1")
    inspect(client.cdp_event_handlers[0].id, content="\{keep_id}")
    client.record_cdp_event({
      method_name: "Inspector.detached",
      params: None,
      session_id: Some("session-1"),
    })
    assert_true(client.attached_target("session-1") is None)
    json_inspect(called, content=["Inspector.detached"])

    client.record_target_attached(
      Some({
        "sessionId": "session-2",
        "targetInfo": {
          "targetId": "target-2",
          "type": "page",
          "title": "No attached flag",
          "url": "about:blank",
        },
      }),
    )
    guard client.attached_target("session-2") is Some(default_target) else {
      fail("expected second attached target")
    }
    inspect(default_target.attached, content="false")
    client.record_target_detached(Some({}))
    client.record_inspector_detached({
      method_name: "Inspector.detached",
      params: None,
      session_id: None,
    })
    client.record_target_detached(None)
    let buffered = client.recv_cdp_event(method_name="Inspector.detached")
    inspect(buffered.method_name, content="Inspector.detached")
  }
}

///|
async test "recv event buffers unrelated pending responses" {
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
      ws.send_text("{\"id\":11,\"result\":{\"ok\":true}}")
      ws.send_text("{\"method\":\"Runtime.consoleAPICalled\",\"params\":{}}")
      try ws.recv() catch {
        _ => ()
      } noraise {
        _ => ()
      }
    }
    let client = CdpClient::connect("ws://127.0.0.1:\{addr.port()}")
    defer client.close()
    client.command_contexts[11] = {
      method_name: "Runtime.evaluate",
      session_id: None,
    }
    let event = client.recv_cdp_event(method_name="Runtime.consoleAPICalled")
    inspect(event.method_name, content="Runtime.consoleAPICalled")
    assert_true(client.pending_responses.get(11) is Some(_))
  }
}

///|
async test "connect with timeout reports websocket handshake failures" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      ignore(conn.read_request())
      conn.send_response(200, "OK", extra_headers={})
      conn.write("not a websocket")
      conn.end_response()
    }
    let result : Result[CdpClient, Error] = try_result_client_client_wbtest_async(() => {
        CdpClient::connect_with_timeout(
          "ws://127.0.0.1:\{addr.port()}",
          timeout_ms=1000,
        )
      },
    )
    guard result is Err(CdpConnectionError::WebSocketHandshakeFailed(_, _)) else {
      fail("expected websocket handshake failure")
    }
  }
}
