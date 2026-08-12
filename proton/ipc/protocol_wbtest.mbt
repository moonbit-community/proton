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
    IpcOpRequest::new("req-version", "app:ping", null).version,
    protocol_version(),
  )
  assert_eq(IpcOpResponse::ok("req-version", null).version, protocol_version())
  assert_eq(
    IpcExtensionEvent::new("ticker", "tick", null).version,
    protocol_version(),
  )
}

///|
test "operation frames round trip through JSON" {
  let request = IpcOpRequest::new("req-1", "app:add", { "left": 1, "right": 2 })
  let parsed_request = parse_ipc_op_request(request.stringify())
  assert_eq(parsed_request, request)
  let response = IpcOpResponse::ok("req-1", 3)
  let parsed_response = parse_ipc_op_response(response.stringify())
  assert_eq(parsed_response, response)
}

///|
test "error responses require a string body" {
  let invalid = IpcOpResponse::{
    version: protocol_version(),
    id: "req-err",
    status: 1,
    body: {},
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
    payload: null,
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
