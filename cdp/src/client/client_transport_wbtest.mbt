///|
async test "response diagnostics precede consumption and cancellation clears state" {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, () => {
      defer server.close()
      let (connection, _) = server.accept()
      defer connection.close()
      let request = connection.read_request()
      let websocket = @websocket.from_http_server(request, connection)
      defer websocket.close()
      ignore(websocket.recv().read_all().text())
      websocket.send_text("{\"id\":1,\"result\":{\"ok\":true}}")
      ignore(websocket.recv().read_all().text())
      let never = @async.CondVar::Cond()
      never.wait()
    })

    let client = CdpClient::connect(group, "ws://127.0.0.1:\{port}")
    defer client.close()
    let first = client.send_cdp_command("Browser.getVersion")
    guard client.pending_commands.get(first) is Some(first_pending) else {
      fail("first CDP command was not registered")
    }
    while first_pending.state is Waiting {
      first_pending.changed.wait()
    }
    guard client.last_cdp_response() is Some(last_response) else {
      fail("received CDP response was not recorded")
    }
    assert_eq(last_response.id, first)
    let mut reuse_rejected = false
    try client.reserve_cdp_command_id(first) catch {
      InvalidField("id") => reuse_rejected = true
      _ => ()
    } noraise {
      _ => ()
    }
    assert_true(reuse_rejected)
    ignore(client.recv_cdp_response(first))

    let second = client.send_cdp_command("Runtime.enable")
    let mut waiting = false
    let wait_started = @async.CondVar::Cond()
    let wait_task = group.spawn(() => {
      waiting = true
      wait_started.broadcast()
      ignore(client.recv_cdp_response(second))
    })
    while !waiting {
      wait_started.wait()
    }
    wait_task.cancel()
    try wait_task.wait() catch {
      _ => ()
    } noraise {
      _ => fail("cancelled CDP wait completed normally")
    }
    assert_false(client.pending_commands.contains(second))
    assert_false(client.command_contexts.contains(second))
  })
}

///|
async test "send failure clears registered command state" {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr.port()
    group.spawn_bg(no_wait=true, () => {
      defer server.close()
      let (connection, _) = server.accept()
      defer connection.close()
      let request = connection.read_request()
      let websocket = @websocket.from_http_server(request, connection)
      defer websocket.close()
      ignore(websocket.recv().read_all().text()) catch {
        _ => ()
      }
    })

    let websocket = @websocket.connect("ws://127.0.0.1:\{port}")
    let client = CdpClient::new(websocket)
    websocket.close()
    let mut failed = false
    try ignore(client.send_cdp_command("Browser.getVersion")) catch {
      _ => failed = true
    } noraise {
      _ => ()
    }
    assert_true(failed)
    assert_eq(client.pending_commands.length(), 0)
    assert_eq(client.command_contexts.length(), 0)
  })
}
