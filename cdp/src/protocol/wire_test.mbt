///|
fn[T, E : Error] try_result_protocol_wire_test(
  f : () -> T raise E,
) -> Result[T, E] {
  try f() catch {
    e => Err(e)
  } noraise {
    value => Ok(value)
  }
}

///|
test "encode cdp command wire json omits absent optional fields" {
  let message = @protocol.cdp_command(id=1, method_name="Page.enable")
  inspect(message.stringify(), content="{\"id\":1,\"method\":\"Page.enable\"}")
}

///|
test "encode cdp command wire json includes params and session" {
  let params : Json = { "url": "https://example.com" }
  let message = @protocol.cdp_command(
    id=7,
    method_name="Page.navigate",
    params~,
    session_id="session-1",
  )
  inspect(
    message.stringify(),
    content="{\"id\":7,\"method\":\"Page.navigate\",\"params\":{\"url\":\"https://example.com\"},\"sessionId\":\"session-1\"}",
  )
}

///|
test "decode cdp response and event messages" {
  let response = @protocol.parse_cdp_incoming(
    @json.parse(
      "{\"id\":7,\"result\":{\"frameId\":\"frame-1\"},\"sessionId\":\"session-1\"}",
    ),
  )
  guard response is Response(resp) else { fail("expected response") }
  inspect(resp.id, content="7")
  assert_true(resp.session_id == Some("session-1"))

  let event = @protocol.parse_cdp_incoming(
    @json.parse(
      "{\"method\":\"Page.loadEventFired\",\"params\":{\"timestamp\":1}}",
    ),
  )
  guard event is Event(evt) else { fail("expected event") }
  inspect(evt.method_name, content="Page.loadEventFired")
}

///|
test "decode cdp error response" {
  let message = @protocol.parse_cdp_incoming(
    @json.parse("{\"id\":9,\"error\":{\"code\":-32000,\"message\":\"failed\"}}"),
  )
  guard message is Response(resp) && resp.error is Some(error) else {
    fail("expected error response")
  }
  inspect(error.code, content="-32000")
  inspect(error.message, content="failed")
}

///|
test "reject non-integer response id" {
  let json = @json.parse("{\"id\":1.5,\"result\":{}}")
  let result : Result[
    @protocol.CdpIncomingMessage,
    @protocol.ProtocolDecodeError,
  ] = try_result_protocol_wire_test(() => @protocol.parse_cdp_incoming(json))
  guard result is Err(InvalidField("id")) else { fail("expected invalid id") }
}

///|
test "reject malformed cdp error and session fields" {
  let missing_error_code : Result[
    @protocol.CdpIncomingMessage,
    @protocol.ProtocolDecodeError,
  ] = try_result_protocol_wire_test(() => {
    @protocol.parse_cdp_incoming({ "id": 1, "error": { "message": "failed" } })
  })
  guard missing_error_code is Err(MissingField("error.code")) else {
    fail("expected missing error code")
  }

  let bad_error_code : Result[
    @protocol.CdpIncomingMessage,
    @protocol.ProtocolDecodeError,
  ] = try_result_protocol_wire_test(() => {
    @protocol.parse_cdp_incoming({
      "id": 1,
      "error": { "code": "bad", "message": "failed" },
    })
  })
  guard bad_error_code is Err(InvalidField("error.code")) else {
    fail("expected invalid error code")
  }

  let bad_error_message : Result[
    @protocol.CdpIncomingMessage,
    @protocol.ProtocolDecodeError,
  ] = try_result_protocol_wire_test(() => {
    @protocol.parse_cdp_incoming({
      "id": 1,
      "error": { "code": -32000, "message": false },
    })
  })
  guard bad_error_message is Err(InvalidField("message")) else {
    fail("expected invalid error message")
  }

  let bad_session : Result[
    @protocol.CdpIncomingMessage,
    @protocol.ProtocolDecodeError,
  ] = try_result_protocol_wire_test(() => {
    @protocol.parse_cdp_incoming({
      "method": "Page.loadEventFired",
      "sessionId": 1,
    })
  })
  guard bad_session is Err(InvalidField("sessionId")) else {
    fail("expected invalid session id")
  }

  let missing_method : Result[
    @protocol.CdpIncomingMessage,
    @protocol.ProtocolDecodeError,
  ] = try_result_protocol_wire_test(() => {
    @protocol.parse_cdp_incoming({ "params": {} })
  })
  guard missing_method is Err(MissingField("method")) else {
    fail("expected missing method")
  }
}
