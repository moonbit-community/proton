///|
test "websocket bridge script embeds launch config" {
  let config = WsIpcLaunchConfig::new("test-token", [49181])
  let script = make_ws_ipc_bridge_script(config, ["app:ping"])
  assert_true(script.contains("test-token"))
  assert_true(script.contains("49181"))
  assert_true(script.contains("app:ping"))
  assert_true(script.contains("WebSocket"))
  assert_true(script.contains("delete pending[id];"))
  assert_true(script.contains("const remoteOpNames = Object.create(null);"))
  assert_true(script.contains("const previousInvokeOp ="))
  assert_true(script.contains("remoteOpNames[name] = true;"))
  assert_true(script.contains("return previousInvokeOp(name, payload);"))
  assert_true(script.contains("let opened = false;"))
  assert_true(script.contains("healthTransport: \"proton-ipc-ws\""))
  assert_true(script.contains("async function healthMatches(response)"))
  assert_true(script.contains("body.transport === config.healthTransport"))
  assert_true(
    script.contains(
      "const ipcProtocolVersion = " + @ipc.protocol_version().to_string(),
    ),
  )
  assert_true(script.contains("function frameVersionMatches(frame)"))
  assert_true(script.contains("function responsePayloadIsValid(response)"))
  assert_true(script.contains("function eventPayloadIsValid(event)"))
  assert_true(script.contains("frame.version === ipcProtocolVersion"))
  assert_true(script.contains("response.version === ipcProtocolVersion"))
  assert_true(script.contains("event.version === ipcProtocolVersion"))
  assert_true(script.contains("version: ipcProtocolVersion"))
  assert_true(
    script.contains("MoonBit WebSocket IPC connection closed before opening"),
  )
}

///|
test "websocket bridge script validation rejects invalid config" {
  match
    validate_ws_ipc_bridge_script_config(WsIpcLaunchConfig::new("", [49181]), [
      "app:ping",
    ]) {
    Err(error) => assert_eq(error, "WebSocket IPC token must not be empty")
    Ok(_) => abort("expected empty bridge token error")
  }
  match
    validate_ws_ipc_bridge_script_config(
      WsIpcLaunchConfig::new("test-token", []),
      ["app:ping"],
    ) {
    Err(error) =>
      assert_eq(error, "WebSocket IPC port candidates must not be empty")
    Ok(_) => abort("expected empty bridge ports error")
  }
}

///|
test "websocket bridge script validation rejects invalid op names" {
  match
    validate_ws_ipc_bridge_script_config(
      WsIpcLaunchConfig::new("test-token", [49181]),
      ["app:ping", " "],
    ) {
    Err(error) =>
      assert_eq(error, "WebSocket IPC bridge op name must not be empty")
    Ok(_) => abort("expected empty bridge op name error")
  }
  match
    validate_ws_ipc_bridge_script_config(
      WsIpcLaunchConfig::new("test-token", [49181]),
      ["app:ping", "app:ping"],
    ) {
    Err(error) =>
      assert_eq(error, "duplicate WebSocket IPC bridge op name: app:ping")
    Ok(_) => abort("expected duplicate bridge op name error")
  }
}

///|
test "ipc token query matching is exact" {
  assert_true(path_has_token("/__proton__/health?token=abc", "abc"))
  assert_true(path_has_token("/__proton__/health?x=1&token=abc", "abc"))
  assert_true(path_has_token("/__proton__/health?token=a%26b%3Dc%25", "a&b=c%"))
  assert_false(path_has_token("/__proton__/health?token=abcx", "abc"))
  assert_false(path_has_token("/__proton__/health?token=abc&token=abc", "abc"))
  assert_false(path_has_token("/__proton__/health?token=abc&token=bad", "abc"))
  assert_false(path_has_token("/__proton__/health?x=token=abc", "abc"))
  assert_false(path_has_token("/__proton__/health?token=a%2", "a%2"))
  assert_true(
    health_url(WsIpcLaunchConfig::new("a&b=c%", [49181]), 49181).contains(
      "token=a%26b%3Dc%25",
    ),
  )
}

///|
test "auto ipc token is opaque hex material" {
  let token = generate_ws_ipc_token()
  @debug.assert_eq(token.length(), 64)
  for ch in token {
    guard (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') else {
      abort("token must be lower-case hex")
    }
  }
}

///|
test "auto ipc token changes between calls" {
  let first = generate_ws_ipc_token()
  let second = generate_ws_ipc_token()
  assert_false(first == second)
}

///|
test "auto ipc config can use caller provided token" {
  match WsIpcLaunchConfig::auto_with_token("external-random-token") {
    Ok(config) => {
      assert_eq(config.token, "external-random-token")
      assert_eq(config.ports.length(), 32)
    }
    Err(error) => abort(error)
  }
  match WsIpcLaunchConfig::auto_with_token("  ") {
    Err(error) => assert_eq(error, "WebSocket IPC token must not be empty")
    Ok(_) => abort("expected empty token error")
  }
  match WsIpcLaunchConfig::auto_with_token("令牌") {
    Err(error) =>
      assert_eq(error, "WebSocket IPC token must be printable ASCII")
    Ok(_) => abort("expected non-ASCII token error")
  }
  match WsIpcLaunchConfig::auto_with_token("token with space") {
    Err(error) =>
      assert_eq(error, "WebSocket IPC token must be printable ASCII")
    Ok(_) => abort("expected token whitespace error")
  }
}

///|
test "ipc health body validation parses JSON fields" {
  let valid =
    #| {
    #|   "version": "1",
    #|   "transport": "proton-ipc-ws",
    #|   "ok": true
    #| }
  assert_true(ws_ipc_health_body_is_valid(valid))
  let misleading =
    #| {
    #|   "ok": false,
    #|   "transport": "wrong",
    #|   "version": "0",
    #|   "note": "\"ok\":true \"transport\":\"proton-ipc-ws\" \"version\":\"1\""
    #| }
  assert_false(ws_ipc_health_body_is_valid(misleading))
}

///|
test "ipc launch config constructor copies port candidates" {
  let ports = [49181]
  let config = WsIpcLaunchConfig::new("test-token", ports)
  ports.push(49182)
  @debug.assert_eq(config.ports, [49181])
}

///|
test "ipc launch config validation keeps transport on loopback" {
  match
    validate_ws_ipc_launch_config(
      WsIpcLaunchConfig::new("test-token", [49181], host="0.0.0.0"),
    ) {
    Err(error) => assert_eq(error, "WebSocket IPC host must be loopback")
    Ok(_) => abort("expected non-loopback host error")
  }
  match
    validate_ws_ipc_launch_config(
      WsIpcLaunchConfig::new("test-token", [49181], host=" 127.0.0.1 "),
    ) {
    Err(error) => assert_eq(error, "WebSocket IPC host must be loopback")
    Ok(_) => abort("expected whitespace host error")
  }
  match
    validate_ws_ipc_launch_config(
      WsIpcLaunchConfig::new("test-token", [49181], host="::1"),
    ) {
    Err(error) => assert_eq(error, "WebSocket IPC host must be loopback")
    Ok(_) => abort("expected bare IPv6 host error")
  }
  match
    validate_ws_ipc_launch_config(
      WsIpcLaunchConfig::new("test-token", [49181], host="[::1]"),
    ) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
  match
    validate_ws_ipc_launch_config(
      WsIpcLaunchConfig::new("test-token", [], host="127.0.0.1"),
    ) {
    Err(error) =>
      assert_eq(error, "WebSocket IPC port candidates must not be empty")
    Ok(_) => abort("expected empty port candidates error")
  }
  match
    validate_ws_ipc_launch_config(
      WsIpcLaunchConfig::new("test-token", [49181, 49181]),
    ) {
    Err(error) =>
      assert_eq(error, "duplicate WebSocket IPC port candidate: 49181")
    Ok(_) => abort("expected duplicate port candidate error")
  }
  match
    validate_ws_ipc_launch_config(WsIpcLaunchConfig::new("test-token", [65535])) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
  match
    validate_ws_ipc_launch_config(
      WsIpcLaunchConfig::new(
        "test-token",
        [49181],
        health_path="__proton__/health",
      ),
    ) {
    Err(error) =>
      assert_eq(error, "WebSocket IPC health path must be an absolute path")
    Ok(_) => abort("expected invalid path error")
  }
  match
    validate_ws_ipc_launch_config(
      WsIpcLaunchConfig::new(
        "test-token",
        [49181],
        ws_path="/__proton__/ws#frag",
      ),
    ) {
    Err(error) =>
      assert_eq(error, "WebSocket IPC websocket path must be an absolute path")
    Ok(_) => abort("expected fragment path error")
  }
  match
    validate_ws_ipc_launch_config(
      WsIpcLaunchConfig::new("test-token", [49181], ws_path="//__proton__/ws"),
    ) {
    Err(error) =>
      assert_eq(error, "WebSocket IPC websocket path must be an absolute path")
    Ok(_) => abort("expected double slash path error")
  }
  match
    validate_ws_ipc_launch_config(
      WsIpcLaunchConfig::new("test-token", [49181], health_path="/"),
    ) {
    Err(error) =>
      assert_eq(error, "WebSocket IPC health path must be an absolute path")
    Ok(_) => abort("expected root path error")
  }
  match
    validate_ws_ipc_launch_config(
      WsIpcLaunchConfig::new(
        "test-token",
        [49181],
        health_path="/__proton__/same",
        ws_path="/__proton__/same",
      ),
    ) {
    Err(error) =>
      assert_eq(
        error, "WebSocket IPC health and websocket paths must be different",
      )
    Ok(_) => abort("expected duplicate health websocket path error")
  }
  match
    validate_ws_ipc_launch_config(
      WsIpcLaunchConfig::new(
        "test-token",
        [49181],
        health_path="/__proton__/bad health",
      ),
    ) {
    Err(error) =>
      assert_eq(error, "WebSocket IPC health path must not contain whitespace")
    Ok(_) => abort("expected whitespace health path error")
  }
}

///|
test "ipc origin policy only allows local webview origins" {
  assert_true(origin_is_allowed(None))
  assert_true(origin_is_allowed(Some("null")))
  assert_true(origin_is_allowed(Some("file://")))
  assert_true(origin_is_allowed(Some("http://localhost:3000")))
  assert_true(origin_is_allowed(Some("https://app.localhost")))
  assert_true(origin_is_allowed(Some("http://127.0.0.1:49181")))
  assert_true(origin_is_allowed(Some("http://[::1]:49181")))
  assert_false(origin_is_allowed(Some("https://example.com")))
  assert_false(origin_is_allowed(Some("https://localhost.evil.example")))
}

///|
async test "websocket ipc event sink waits for valid config" {
  let config = WsIpcLaunchConfig::new("test-token-invalid-sink", [])
  let mut installed = false
  match
    run_ws_ipc_server_with_event_sink(
      config,
      fn(request) { @ipc.IpcOpResponse::ok(request.id, Json::string("ok")) },
      event_sink=fn(_emit) { installed = true },
    ) {
    Err(error) =>
      assert_eq(error, "WebSocket IPC port candidates must not be empty")
    Ok(_) => abort("expected invalid IPC config error")
  }
  assert_false(installed)
}

///|
async test "websocket ipc event sink waits for successful bind" {
  let occupied = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer occupied.close()
  let config = WsIpcLaunchConfig::new("test-token-bind-failure", [
    occupied.addr.port(),
  ])
  let mut installed = false
  match
    run_ws_ipc_server_with_event_sink(
      config,
      fn(request) { @ipc.IpcOpResponse::ok(request.id, Json::string("ok")) },
      event_sink=fn(_emit) { installed = true },
    ) {
    Err(error) =>
      assert_eq(error, "failed to bind any WebSocket IPC candidate port")
    Ok(_) => abort("expected IPC bind failure")
  }
  assert_false(installed)
}

///|
async test "websocket ipc health limits cors origins" {
  let config = WsIpcLaunchConfig::new("test-token-origin-health", [49184])
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      ignore(
        run_ws_ipc_server(config, fn(request) {
          @ipc.IpcOpResponse::ok(request.id, Json::string("ok"))
        }),
      )
    })
    let port = match wait_ws_ipc_ready_async(config, 2000, 25) {
      Ok(port) => port
      Err(error) => abort(error)
    }
    let url = health_url(config, port)
    let (allowed_response, allowed_body) = @http.get(url, headers={
      "Origin": "https://app.localhost",
    })
    @debug.assert_eq(allowed_response.code, 200)
    @debug.assert_eq(
      header_value(allowed_response.headers, "access-control-allow-origin"),
      Some("https://app.localhost"),
    )
    assert_true(ws_ipc_health_body_is_valid(allowed_body.text()))

    let (denied_response, _denied_body) = @http.get(url, headers={
      "Origin": "https://example.com",
    })
    @debug.assert_eq(denied_response.code, 403)
    @debug.assert_eq(
      header_value(denied_response.headers, "access-control-allow-origin"),
      None,
    )
  })
}

///|
async test "websocket ipc rejects remote websocket origins" {
  let config = WsIpcLaunchConfig::new("test-token-origin-ws", [49185])
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      ignore(
        run_ws_ipc_server(config, fn(request) {
          @ipc.IpcOpResponse::ok(request.id, Json::string("ok"))
        }),
      )
    })
    let port = match wait_ws_ipc_ready_async(config, 2000, 25) {
      Ok(port) => port
      Err(error) => abort(error)
    }
    try
      @websocket.connect(
        "ws://" +
        config.host +
        ":" +
        port.to_string() +
        config.ws_path +
        "?token=" +
        config.token,
        headers={ "Origin": "https://example.com" },
      )
    catch {
      _ => ()
    } noraise {
      ws => {
        ws.close()
        abort("expected remote websocket origin to be rejected")
      }
    }
  })
}

///|
async test "websocket ipc rejects plain http websocket path" {
  let config = WsIpcLaunchConfig::new("test-token-invalid-upgrade", [49187])
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      ignore(
        run_ws_ipc_server(config, fn(request) {
          @ipc.IpcOpResponse::ok(request.id, Json::string("ok"))
        }),
      )
    })
    let port = match wait_ws_ipc_ready_async(config, 2000, 25) {
      Ok(port) => port
      Err(error) => abort(error)
    }
    let (response, body) = @http.get(
      "http://" +
      config.host +
      ":" +
      port.to_string() +
      config.ws_path +
      "?token=" +
      config.token,
    )
    @debug.assert_eq(response.code, 400)
    @debug.assert_eq(body.text(), "Missing or invalid Upgrade header")
  })
}

///|
async test "websocket ipc event sink can emit after response" {
  let config = WsIpcLaunchConfig::new("test-token-event-sink", [49182])
  let mut emit_sink : (async (@ipc.IpcExtensionEvent) -> Unit)? = None
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      ignore(
        run_ws_ipc_server_with_event_sink(
          config,
          fn(request) {
            @ipc.IpcOpResponse::ok(request.id, Json::string("ready"))
          },
          event_sink=fn(emit) { emit_sink = Some(emit) },
        ),
      )
    })
    let port = match wait_ws_ipc_ready_async(config, 2000, 25) {
      Ok(port) => port
      Err(error) => abort(error)
    }
    let ws = @websocket.connect(
      "ws://" +
      config.host +
      ":" +
      port.to_string() +
      config.ws_path +
      "?token=" +
      config.token,
    )
    defer ws.close()
    ws.send_text(
      @ipc.IpcFrame::request(
        @ipc.IpcOpRequest::new("req-1", "ext:ticker/start", Json::null()),
      ).stringify(),
    )
    let response_frame = match
      @ipc.parse_ipc_frame(ws.recv().read_all().text()) {
      Ok(frame) => frame
      Err(error) => abort(error)
    }
    @debug.assert_eq(response_frame.kind, "response")
    let response = match response_frame.as_response() {
      Ok(response) => response
      Err(error) => abort(error)
    }
    @debug.assert_eq(
      response,
      @ipc.IpcOpResponse::ok("req-1", Json::string("ready")),
    )

    match emit_sink {
      Some(emit) => {
        emit(@ipc.IpcExtensionEvent::new("", "bad", Json::null()))
        emit(@ipc.IpcExtensionEvent::new("ticker", "", Json::null()))
        emit(
          @ipc.IpcExtensionEvent::new(
            "ticker",
            "done",
            Json::object({ "ok": Json::boolean(true) }),
          ),
        )
      }
      None => abort("event sink was not installed")
    }
    let event_frame = match @ipc.parse_ipc_frame(ws.recv().read_all().text()) {
      Ok(frame) => frame
      Err(error) => abort(error)
    }
    @debug.assert_eq(event_frame.kind, "event")
    let event = match event_frame.as_event() {
      Ok(event) => event
      Err(error) => abort(error)
    }
    @debug.assert_eq(event.extension_namespace, "ticker")
    @debug.assert_eq(event.event_name, "done")
  })
}

///|
async test "websocket ipc dispatches same-connection requests concurrently" {
  let config = WsIpcLaunchConfig::new("test-token-concurrent", [49183])
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      ignore(
        run_ws_ipc_server(config, async fn(request) {
          if request.id == "slow" {
            @async.sleep(250)
          }
          @ipc.IpcOpResponse::ok(request.id, Json::string(request.id))
        }),
      )
    })
    let port = match wait_ws_ipc_ready_async(config, 2000, 25) {
      Ok(port) => port
      Err(error) => abort(error)
    }
    let ws = @websocket.connect(
      "ws://" +
      config.host +
      ":" +
      port.to_string() +
      config.ws_path +
      "?token=" +
      config.token,
    )
    defer ws.close()
    ws.send_text(
      @ipc.IpcFrame::request(
        @ipc.IpcOpRequest::new("slow", "ext:test/slow", Json::null()),
      ).stringify(),
    )
    ws.send_text(
      @ipc.IpcFrame::request(
        @ipc.IpcOpRequest::new("fast", "ext:test/fast", Json::null()),
      ).stringify(),
    )
    let first_frame = match @ipc.parse_ipc_frame(ws.recv().read_all().text()) {
      Ok(frame) => frame
      Err(error) => abort(error)
    }
    let first_response = match first_frame.as_response() {
      Ok(response) => response
      Err(error) => abort(error)
    }
    @debug.assert_eq(
      first_response,
      @ipc.IpcOpResponse::ok("fast", Json::string("fast")),
    )
  })
}

///|
async test "websocket ipc wraps invalid dispatch responses" {
  let config = WsIpcLaunchConfig::new("test-token-invalid-response", [49186])
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      ignore(
        run_ws_ipc_server(config, fn(_request) {
          @ipc.IpcOpResponse::ok("", Json::null())
        }),
      )
    })
    let port = match wait_ws_ipc_ready_async(config, 2000, 25) {
      Ok(port) => port
      Err(error) => abort(error)
    }
    let ws = @websocket.connect(
      "ws://" +
      config.host +
      ":" +
      port.to_string() +
      config.ws_path +
      "?token=" +
      config.token,
    )
    defer ws.close()
    ws.send_text(
      @ipc.IpcFrame::request(
        @ipc.IpcOpRequest::new("req-invalid", "ext:test/bad", Json::null()),
      ).stringify(),
    )
    let frame = match @ipc.parse_ipc_frame(ws.recv().read_all().text()) {
      Ok(frame) => frame
      Err(error) => abort(error)
    }
    let response = match frame.as_response() {
      Ok(response) => response
      Err(error) => abort(error)
    }
    @debug.assert_eq(
      response,
      @ipc.IpcOpResponse::err(
        "req-invalid", "invalid IPC response: IPC response id must not be empty",
      ),
    )
  })
}
