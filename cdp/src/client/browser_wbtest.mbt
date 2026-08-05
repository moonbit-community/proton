///|
fn[T, E : Error] try_result_client_browser_wbtest(
  f : () -> T raise E,
) -> Result[T, E] {
  try f() catch {
    e => Err(e)
  } noraise {
    value => Ok(value)
  }
}

///|
test "browser response helpers parse target metadata and errors" {
  let target = parse_target_info({
    "targetId": "target-1",
    "type": "page",
    "title": "Example",
    "url": "https://example.com/",
    "attached": true,
    "browserContextId": "context-1",
  })
  inspect(target.target_id, content="target-1")
  inspect(target.target_type, content="page")
  guard target.browser_context_id is Some("context-1") else {
    fail("expected browser context id")
  }

  let default_attached = parse_target_info({
    "targetId": "target-2",
    "type": "worker",
    "title": "Worker",
    "url": "https://example.com/sw.js",
  })
  inspect(default_attached.attached, content="false")
  assert_true(default_attached.browser_context_id is None)

  let invalid_target : Result[CdpTargetInfo, Error] = try_result_client_browser_wbtest(() => {
      parse_target_info([])
    },
  )
  guard invalid_target is Err(BrowserError::InvalidField("targetInfos[]")) else {
    fail("expected invalid targetInfo object")
  }

  let invalid_attached : Result[CdpTargetInfo, Error] = try_result_client_browser_wbtest(() => {
      parse_target_info({
        "targetId": "target-3",
        "type": "page",
        "title": "Bad",
        "url": "https://example.com/",
        "attached": "yes",
      })
    },
  )
  guard invalid_attached is Err(BrowserError::InvalidField("attached")) else {
    fail("expected invalid attached field")
  }
}

///|
test "browser response helpers classify result shapes" {
  let ok_response : @protocol.CdpResponseMessage = {
    id: 1,
    result: Some({ "targetId": "target-1" }),
    error: None,
    session_id: None,
  }
  let result = response_result(ok_response)
  inspect(required_string(result, "targetId"), content="target-1")
  json_inspect(cdp_response_result_json(ok_response), content={
    "targetId": "target-1",
  })

  let empty_response : @protocol.CdpResponseMessage = {
    id: 2,
    result: None,
    error: None,
    session_id: None,
  }
  json_inspect(cdp_response_result_json(empty_response), content={})
  let missing_result : Result[Map[String, Json], Error] = try_result_client_browser_wbtest(() => {
      response_result(empty_response)
    },
  )
  guard missing_result is Err(BrowserError::MissingField("result")) else {
    fail("expected missing result")
  }

  let array_response : @protocol.CdpResponseMessage = {
    id: 3,
    result: Some([]),
    error: None,
    session_id: None,
  }
  let invalid_result : Result[Map[String, Json], Error] = try_result_client_browser_wbtest(() => {
      response_result(array_response)
    },
  )
  guard invalid_result is Err(BrowserError::InvalidField("result")) else {
    fail("expected invalid result")
  }
  let missing_json : Result[Json, Error] = try_result_client_browser_wbtest(() => {
    required_json(result, "missing")
  })
  guard missing_json is Err(BrowserError::MissingField("missing")) else {
    fail("expected missing json field")
  }

  let error_response : @protocol.CdpResponseMessage = {
    id: 4,
    result: None,
    error: Some({ code: -32000, message: "failed", data: None }),
    session_id: None,
  }
  let failed : Result[Map[String, Json], Error] = try_result_client_browser_wbtest(() => {
      response_result(error_response)
    },
  )
  guard failed is Err(BrowserError::CommandFailed(-32000, "failed")) else {
    fail("expected command failure")
  }
  let failed_json : Result[Json, Error] = try_result_client_browser_wbtest(() => {
    cdp_response_result_json(error_response)
  })
  guard failed_json is Err(BrowserError::CommandFailed(-32000, "failed")) else {
    fail("expected command failure from json helper")
  }
}

///|
test "browser scalar helpers reject missing and invalid fields" {
  let fields : Map[String, Json] = {
    "string": "value",
    "bool": true,
    "bad_string": false,
    "bad_bool": "true",
  }
  inspect(required_string(fields, "string"), content="value")
  guard optional_string(fields, "string") is Some("value") else {
    fail("expected optional string")
  }
  guard optional_bool(fields, "bool") is Some(true) else {
    fail("expected optional bool")
  }
  assert_true(optional_string(fields, "missing") is None)
  assert_true(optional_bool(fields, "missing") is None)

  let missing : Result[String, Error] = try_result_client_browser_wbtest(() => {
    required_string(fields, "missing")
  })
  guard missing is Err(BrowserError::MissingField("missing")) else {
    fail("expected missing field")
  }
  let bad_string : Result[String, Error] = try_result_client_browser_wbtest(() => {
    required_string(fields, "bad_string")
  })
  guard bad_string is Err(BrowserError::InvalidField("bad_string")) else {
    fail("expected invalid string")
  }
  let bad_optional_string : Result[String?, Error] = try_result_client_browser_wbtest(() => {
      optional_string(fields, "bad_string")
    },
  )
  guard bad_optional_string is Err(BrowserError::InvalidField("bad_string")) else {
    fail("expected invalid optional string")
  }
  let bad_optional_bool : Result[Bool?, Error] = try_result_client_browser_wbtest(() => {
      optional_bool(fields, "bad_bool")
    },
  )
  guard bad_optional_bool is Err(BrowserError::InvalidField("bad_bool")) else {
    fail("expected invalid optional bool")
  }
  inspect(checked_duration(1, "timeout_ms"), content="1")
  let bad_duration : Result[Int, Error] = try_result_client_browser_wbtest(() => {
    checked_duration(0, "timeout_ms")
  })
  guard bad_duration is Err(BrowserError::InvalidField("timeout_ms")) else {
    fail("expected invalid duration")
  }
}

///|
async test "browser target helpers send schema commands" {
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

      let get_targets = ws.recv().read_all().text()
      assert_true(get_targets.contains("\"method\":\"Target.getTargets\""))
      ws.send_text(
        "{\"id\":1,\"result\":{\"targetInfos\":[{\"targetId\":\"target-1\",\"type\":\"page\",\"title\":\"Example\",\"url\":\"https://example.com/\",\"attached\":false}]}}",
      )

      let create_target = ws.recv().read_all().text()
      assert_true(create_target.contains("\"method\":\"Target.createTarget\""))
      assert_true(create_target.contains("\"browserContextId\":\"context-1\""))
      assert_true(create_target.contains("\"newWindow\":true"))
      ws.send_text("{\"id\":2,\"result\":{\"targetId\":\"target-2\"}}")
    }
    let client = CdpClient::connect("ws://127.0.0.1:\{addr.port()}")
    defer client.close()
    let targets = client.get_targets()
    inspect(targets.length(), content="1")
    inspect(targets[0].target_id, content="target-1")
    let target_id = client.create_target(
      url="https://example.com/",
      browser_context_id="context-1",
      new_window=true,
    )
    inspect(target_id, content="target-2")
  }
}

///|
test "browser target info list parser rejects invalid target list shape" {
  let result : Result[Array[CdpTargetInfo], Error] = try_result_client_browser_wbtest(() => {
      parse_target_infos({ "targetInfos": {} })
    },
  )
  guard result is Err(BrowserError::InvalidField("targetInfos")) else {
    fail("expected invalid targetInfos")
  }
}
