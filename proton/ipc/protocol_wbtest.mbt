///|
fn[T] expect_ipc_error(action : () -> T raise IpcError) -> IpcError raise {
  try action() catch {
    error => error
  } noraise {
    _ => fail("expected IPC error")
  }
}

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
  let parsed_request = parse_ipc_op_request(request.stringify())
  assert_eq(parsed_request, request)
  let response = IpcOpResponse::ok("req-1", Json::number(3))
  let parsed_response = parse_ipc_op_response(response.stringify())
  assert_eq(parsed_response, response)
}

///|
test "error responses require a string body" {
  let invalid = IpcOpResponse::{
    version: protocol_version(),
    id: "req-err",
    status: 1,
    body: Json::empty_object(),
  }
  let error = expect_ipc_error(() => invalid.validate())
  assert_eq(error, IpcError::InvalidErrorResponseBody)
}

///|
test "decoded requests expose reusable validation" {
  let invalid = IpcOpRequest::{
    version: protocol_version() + 1,
    id: "req-invalid-version",
    name: "app:ping",
    payload: Json::null(),
  }
  let error = expect_ipc_error(() => invalid.validate())
  assert_eq(
    error,
    IpcError::UnsupportedVersion(
      scope="protocol",
      actual=protocol_version() + 1,
      supported=protocol_version(),
    ),
  )
}

///|
test "transport frames decode by kind" {
  let request = IpcOpRequest::new("req-2", "app:ping", Json::null())
  let frame = IpcFrame::request(request)
  let parsed_request = parse_ipc_frame(frame.stringify()).as_request()
  assert_eq(parsed_request, request)
}

///|
test "event frames validate payload shape" {
  let event = IpcExtensionEvent::new("ticker", "tick", Json::null())
  let parsed_event = parse_ipc_frame(IpcFrame::event(event).stringify()).as_event()
  assert_eq(parsed_event, event)

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
  let error = expect_ipc_error(() => invalid_event.as_event())
  assert_eq(error, IpcError::EmptyField(path="IPC event extension namespace"))
}

///|
test "frame decoders validate outer envelope" {
  let request = IpcOpRequest::new("req-3", "app:ping", Json::null())
  let invalid_version = IpcFrame::{
    version: protocol_version() + 1,
    kind: "request",
    payload: ToJson::to_json(request),
  }
  let error = expect_ipc_error(() => invalid_version.as_request())
  assert_eq(
    error,
    IpcError::UnsupportedVersion(
      scope="frame",
      actual=protocol_version() + 1,
      supported=protocol_version(),
    ),
  )

  let invalid_kind = IpcFrame::{
    version: protocol_version(),
    kind: "unknown",
    payload: ToJson::to_json(request),
  }
  let error = expect_ipc_error(() => invalid_kind.as_request())
  assert_eq(error, IpcError::UnsupportedFrameKind(kind="unknown"))
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
