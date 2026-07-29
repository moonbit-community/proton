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
