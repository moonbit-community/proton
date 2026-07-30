///|
struct EchoRequest {
  value : String
} derive(ToJson)

///|
struct EchoResponse {
  value : String
} derive(FromJson, Eq, Debug)

///|
struct CountChanged {
  count : Int
} derive(FromJson, Eq, Debug)

///|
struct CallbackOutcome {
  response : EchoResponse?
  failure : ClientFailure?
  route : String
  request_json : String
}

///|
extern "js" fn install_fake_bridge(
  response_json : String,
  failure_json? : String = "",
) -> Unit =
  #| (responseJson, failureJson) => {
  #|   globalThis.__protonClientTest = {
  #|     route: "",
  #|     requestJson: "",
  #|     listeners: new Map(),
  #|   };
  #|   globalThis.__MoonBit__ = {
  #|     core: {
  #|       invokeJson(route, requestJson) {
  #|         globalThis.__protonClientTest.route = route;
  #|         globalThis.__protonClientTest.requestJson = requestJson;
  #|         if (failureJson !== "") {
  #|           return Promise.reject(JSON.parse(failureJson));
  #|         }
  #|         return Promise.resolve(responseJson);
  #|       },
  #|     },
  #|     events: {
  #|       onJson(route, listener) {
  #|         globalThis.__protonClientTest.listeners.set(route, listener);
  #|         return () => globalThis.__protonClientTest.listeners.delete(route);
  #|       },
  #|     },
  #|   };
  #| }

///|
extern "js" fn install_fake_callback_bridge(
  response_json : String,
  failure_json? : String = "",
) -> Unit =
  #| (responseJson, failureJson) => {
  #|   globalThis.__protonClientTest = {
  #|     route: "",
  #|     requestJson: "",
  #|     listeners: new Map(),
  #|   };
  #|   globalThis.__MoonBit__ = {
  #|     core: {
  #|       invokeJson(route, requestJson) {
  #|         globalThis.__protonClientTest.route = route;
  #|         globalThis.__protonClientTest.requestJson = requestJson;
  #|         return {
  #|           then(success, failure) {
  #|             if (failureJson !== "") {
  #|               failure(JSON.parse(failureJson));
  #|             } else {
  #|               success(responseJson);
  #|             }
  #|           },
  #|         };
  #|       },
  #|     },
  #|   };
  #| }

///|
extern "js" fn remove_fake_bridge() -> Unit =
  #| () => {
  #|   delete globalThis.__MoonBit__;
  #|   delete globalThis.__protonClientTest;
  #| }

///|
extern "js" fn fake_route() -> String =
  #| () => globalThis.__protonClientTest.route

///|
extern "js" fn fake_request_json() -> String =
  #| () => globalThis.__protonClientTest.requestJson

///|
extern "js" fn emit_fake_event(route : String, payload_json : String) -> Unit =
  #| (route, payloadJson) => {
  #|   const listener = globalThis.__protonClientTest.listeners.get(route);
  #|   if (listener) listener(payloadJson);
  #| }

///|
extern "js" fn fake_has_listener(route : String) -> Bool =
  #| (route) => globalThis.__protonClientTest.listeners.has(route)

///|
fn invoke_callback_outcome(
  response_json : String,
  failure_json? : String = "",
) -> CallbackOutcome {
  install_fake_callback_bridge(response_json, failure_json~)
  defer remove_fake_bridge()
  let response : Ref[EchoResponse?] = Ref(None)
  let failure : Ref[ClientFailure?] = Ref(None)
  let echo : @proton_contract.Command[EchoRequest, EchoResponse] = @proton_contract.command(
    "callback_echo",
  )
  invoke_with_callbacks(
    echo,
    { value: "ping" },
    value => response.val = Some(value),
    error => failure.val = Some(error),
  )
  {
    response: response.val,
    failure: failure.val,
    route: fake_route(),
    request_json: fake_request_json(),
  }
}

///|
async test "client uses typed JSON commands and live events" {
  install_fake_bridge("{\"value\":\"pong\"}")
  let echo : @proton_contract.Command[EchoRequest, EchoResponse] = @proton_contract.command(
    "echo",
  )
  let response = invoke(echo, { value: "ping" })
  assert_eq(response, EchoResponse::{ value: "pong" })
  inspect(fake_route(), content="app:echo")
  inspect(fake_request_json(), content="{\"value\":\"ping\"}")
  let changed : @proton_contract.Event[CountChanged] = @proton_contract.event(
    "count_changed",
  )
  let mut count = 0
  let mut failures = 0
  let subscription = subscribe(changed, payload => count = payload.count, _ => {
    failures += 1
  })
  emit_fake_event("app:count_changed", "{\"count\":7}")
  assert_eq(count, 7)
  assert_eq(failures, 0)
  emit_fake_event("app:count_changed", "not json")
  assert_eq(failures, 1)
  subscription.close()
  subscription.close()
  assert_false(fake_has_listener("app:count_changed"))
  remove_fake_bridge()
  try {
    ignore(invoke(echo, { value: "ping" }))
    fail("expected BridgeUnavailable")
  } catch {
    ClientFailure::BridgeUnavailable => ()
    _ => fail("expected BridgeUnavailable")
  }
}

///|
test "client preserves stable remote error codes" {
  assert_eq(
    decode_bridge_failure(
      "{\"code\":\"request_timeout\",\"message\":\"bridge request timed out\"}",
    ),
    ClientFailure::RequestTimedOut,
  )
  assert_eq(
    decode_bridge_failure(
      "{\"code\":\"backend_failed\",\"message\":\"command failed\",\"detail\":\"validation\"}",
    ),
    ClientFailure::RemoteFailure(
      code="backend_failed",
      message="command failed",
      detail=Some("validation"),
    ),
  )
}

///|
async test "client maps bridge timeout rejection through invoke" {
  install_fake_bridge(
    "",
    failure_json="{\"code\":\"request_timeout\",\"message\":\"bridge request timed out\"}",
  )
  defer remove_fake_bridge()
  let echo : @proton_contract.Command[EchoRequest, EchoResponse] = @proton_contract.command(
    "echo",
  )
  try {
    ignore(invoke(echo, { value: "ping" }))
    fail("expected RequestTimedOut")
  } catch {
    ClientFailure::RequestTimedOut => ()
    error => fail("expected RequestTimedOut, got " + error.to_string())
  }
}

///|
async test "client preserves remote error detail through invoke" {
  install_fake_bridge(
    "",
    failure_json="{\"code\":\"backend_failed\",\"message\":\"command failed\",\"detail\":\"validation\"}",
  )
  defer remove_fake_bridge()
  let echo : @proton_contract.Command[EchoRequest, EchoResponse] = @proton_contract.command(
    "echo",
  )
  try {
    ignore(invoke(echo, { value: "ping" }))
    fail("expected RemoteFailure")
  } catch {
    ClientFailure::RemoteFailure(code~, message~, detail~) => {
      assert_eq(code, "backend_failed")
      assert_eq(message, "command failed")
      assert_eq(detail, Some("validation"))
    }
    error => fail("expected RemoteFailure, got " + error.to_string())
  }
}

///|
async test "client maps cancellation rejection through invoke" {
  install_fake_bridge(
    "",
    failure_json="{\"code\":\"request_cancelled\",\"message\":\"request cancelled\"}",
  )
  defer remove_fake_bridge()
  let echo : @proton_contract.Command[EchoRequest, EchoResponse] = @proton_contract.command(
    "echo",
  )
  try {
    ignore(invoke(echo, { value: "ping" }))
    fail("expected RequestCancelled")
  } catch {
    ClientFailure::RequestCancelled => ()
    error => fail("expected RequestCancelled, got " + error.to_string())
  }
}

///|
async test "client maps unclassified bridge rejection to transport failure" {
  install_fake_bridge("", failure_json="{\"message\":\"connection reset\"}")
  defer remove_fake_bridge()
  let echo : @proton_contract.Command[EchoRequest, EchoResponse] = @proton_contract.command(
    "echo",
  )
  try {
    ignore(invoke(echo, { value: "ping" }))
    fail("expected TransportFailure")
  } catch {
    ClientFailure::TransportFailure(message~) =>
      assert_eq(message, "connection reset")
    error => fail("expected TransportFailure, got " + error.to_string())
  }
}

///|
async test "client reports response decoding failures through invoke" {
  install_fake_bridge("{\"unexpected\":true}")
  defer remove_fake_bridge()
  let echo : @proton_contract.Command[EchoRequest, EchoResponse] = @proton_contract.command(
    "echo",
  )
  try {
    ignore(invoke(echo, { value: "ping" }))
    fail("expected ResponseDecode")
  } catch {
    ClientFailure::ResponseDecode(message~) =>
      assert_true(message.contains("value"))
    error => fail("expected ResponseDecode, got " + error.to_string())
  }
}

///|
test "callback invocation serializes requests and decodes responses" {
  let outcome = invoke_callback_outcome("{\"value\":\"pong\"}")
  assert_eq(outcome.response, Some(EchoResponse::{ value: "pong" }))
  assert_eq(outcome.failure, None)
  assert_eq(outcome.route, "app:callback_echo")
  assert_eq(outcome.request_json, "{\"value\":\"ping\"}")
}

///|
test "callback invocation reports synchronous preflight failures" {
  let response_called = Ref(false)
  let failure : Ref[ClientFailure?] = Ref(None)
  let invalid : @proton_contract.Command[EchoRequest, EchoResponse] = @proton_contract.command(
    "",
  )
  invoke_with_callbacks(
    invalid,
    { value: "ping" },
    _value => response_called.val = true,
    error => failure.val = Some(error),
  )
  assert_false(response_called.val)
  match failure.val {
    Some(ClientFailure::InvalidContract(message~)) =>
      assert_true(message.contains("must not be empty"))
    _ => fail("expected InvalidContract")
  }

  remove_fake_bridge()
  failure.val = None
  let echo : @proton_contract.Command[EchoRequest, EchoResponse] = @proton_contract.command(
    "callback_bridge_unavailable",
  )
  invoke_with_callbacks(
    echo,
    { value: "ping" },
    _value => response_called.val = true,
    error => failure.val = Some(error),
  )
  assert_false(response_called.val)
  assert_eq(failure.val, Some(ClientFailure::BridgeUnavailable))
}

///|
test "callback invocation preserves structured bridge failures" {
  let remote = invoke_callback_outcome(
    "",
    failure_json="{\"code\":\"backend_failed\",\"message\":\"command failed\",\"detail\":\"validation\"}",
  )
  assert_eq(remote.response, None)
  assert_eq(
    remote.failure,
    Some(
      ClientFailure::RemoteFailure(
        code="backend_failed",
        message="command failed",
        detail=Some("validation"),
      ),
    ),
  )

  let timeout = invoke_callback_outcome(
    "",
    failure_json="{\"code\":\"request_timeout\",\"message\":\"bridge request timed out\"}",
  )
  assert_eq(timeout.response, None)
  assert_eq(timeout.failure, Some(ClientFailure::RequestTimedOut))

  let cancelled = invoke_callback_outcome(
    "",
    failure_json="{\"code\":\"request_cancelled\",\"message\":\"request cancelled\"}",
  )
  assert_eq(cancelled.response, None)
  assert_eq(cancelled.failure, Some(ClientFailure::RequestCancelled))

  let transport = invoke_callback_outcome(
    "",
    failure_json="{\"message\":\"connection reset\"}",
  )
  assert_eq(transport.response, None)
  assert_eq(
    transport.failure,
    Some(ClientFailure::TransportFailure(message="connection reset")),
  )
}

///|
test "callback invocation reports response decoding failures" {
  let outcome = invoke_callback_outcome("{\"unexpected\":true}")
  assert_eq(outcome.response, None)
  match outcome.failure {
    Some(ClientFailure::ResponseDecode(message~)) =>
      assert_true(message.contains("value"))
    _ => fail("expected ResponseDecode")
  }
}
