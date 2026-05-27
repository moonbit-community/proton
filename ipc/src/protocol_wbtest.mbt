///|
test "protocol version is shared by constructors" {
  assert_eq(protocol_version(), 1)
  assert_eq(
    IpcFrame::request(
      IpcOpRequest::new("req-version", "app:ping", Json::null()),
    ).version,
    protocol_version(),
  )
}

///|
test "operation frames round trip through JSON" {
  let request = IpcOpRequest::new(
    "req-1",
    "app:add",
    Json::object({ "left": Json::number(1), "right": Json::number(2) }),
  )
  guard parse_ipc_op_request(request.stringify()) is Ok(parsed_request) &&
    parsed_request == request else {
    fail("request should round trip")
  }
  let response = IpcOpResponse::ok("req-1", Json::number(3))
  guard parse_ipc_op_response(response.stringify()) is Ok(parsed_response) &&
    parsed_response == response else {
    fail("response should round trip")
  }
}

///|
test "error responses require a string body" {
  let invalid = IpcOpResponse::{
    version: protocol_version(),
    id: "req-err",
    status: 1,
    body: Json::object({}),
  }
  guard invalid.validate() is Err(message) &&
    message == "IPC error response body must be a string" else {
    fail("error response should reject non-string body")
  }
}

///|
test "decoded requests expose reusable validation" {
  let invalid = IpcOpRequest::{
    version: protocol_version() + 1,
    id: "req-invalid-version",
    name: "app:ping",
    payload: Json::null(),
  }
  guard invalid.validate() is Err(message) &&
    message ==
    "Unsupported IPC protocol version: " + (protocol_version() + 1).to_string() else {
    fail("request validation should reject unsupported versions")
  }
}

///|
test "transport frames decode by kind" {
  let request = IpcOpRequest::new("req-2", "app:ping", Json::null())
  let frame = IpcFrame::request(request)
  guard parse_ipc_frame(frame.stringify()).bind(fn(f) { f.as_request() })
    is Ok(parsed_request) &&
    parsed_request == request else {
    fail("request frame should decode")
  }
}

///|
test "event frames validate payload shape" {
  let event = IpcExtensionEvent::new("ticker", "tick", Json::null())
  guard parse_ipc_frame(IpcFrame::event(event).stringify()).bind(fn(frame) {
      frame.as_event()
    })
    is Ok(parsed_event) &&
    parsed_event == event else {
    fail("event frame should decode")
  }

  let invalid_event = IpcFrame::{
    version: 1,
    kind: "event",
    payload: Json::object({
      "version": Json::number(1),
      "extension_namespace": Json::string(""),
      "event_name": Json::string("tick"),
      "payload": Json::null(),
    }),
  }
  guard invalid_event.as_event() is Err(message) &&
    message == "IPC event extension namespace must not be empty" else {
    fail("event frame should reject empty namespace")
  }
}

///|
test "frame decoders validate outer envelope" {
  let request = IpcOpRequest::new("req-3", "app:ping", Json::null())
  let invalid_version = IpcFrame::{
    version: protocol_version() + 1,
    kind: "request",
    payload: ToJson::to_json(request),
  }
  guard invalid_version.as_request() is Err(message) &&
    message ==
    "Unsupported IPC frame version: " + (protocol_version() + 1).to_string() else {
    fail("request decoder should reject unsupported frame version")
  }

  let invalid_kind = IpcFrame::{
    version: protocol_version(),
    kind: "unknown",
    payload: ToJson::to_json(request),
  }
  guard invalid_kind.as_request() is Err(message) &&
    message == "Unsupported IPC frame kind: unknown" else {
    fail("request decoder should reject unsupported frame kind")
  }
}

///|
test "extension descriptor copies mutable array inputs" {
  let apis = [IpcExtensionApi::new("ping")]
  let scripts = ["window.__demo = true;"]
  let descriptor = IpcExtensionDescriptor::new(
    "vendor/demo",
    "demo",
    apis,
    scripts~,
  )
  apis.push(IpcExtensionApi::new("later"))
  scripts.push("window.__demo = false;")
  assert_eq(descriptor.apis.length(), 1)
  assert_eq(descriptor.scripts.length(), 1)
}
