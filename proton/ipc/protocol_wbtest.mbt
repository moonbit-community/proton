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
  assert_eq(protocol_version(), 2)
  assert_eq(
    IpcOpRequest("req-version", "app:ping", null).version,
    protocol_version(),
  )
  assert_eq(IpcOpResponse::ok("req-version", null).version, protocol_version())
  assert_eq(
    IpcExtensionEvent("ticker", "tick", null).version,
    protocol_version(),
  )
}

///|
test "operation frames round trip through JSON" {
  let request = IpcOpRequest("req-1", "app:add", { "left": 1, "right": 2 })
  let parsed_request = parse_ipc_op_request(request.stringify())
  assert_eq(parsed_request, request)
  let response = IpcOpResponse::ok("req-1", 3)
  let parsed_response = parse_ipc_op_response(response.stringify())
  assert_eq(parsed_response, response)
}

///|
test "error responses require a structured body" {
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
  let apis = [IpcExtensionApi("ping")]
  let scripts = ["window.__demo = true;"]
  let descriptor = IpcExtensionDescriptor("vendor/demo", "demo", apis, scripts~)
  apis.push(IpcExtensionApi("later"))
  scripts.push("window.__demo = false;")
  assert_eq(descriptor.apis.length(), 1)
  assert_eq(descriptor.scripts.length(), 1)
}

///|
test "structured command failures round trip without losing classification" {
  let response = IpcOpResponse::err("failure-1", {
    code: "invalid_payload",
    message: "invalid command payload",
    detail: Some("field name is required"),
  })
  let decoded = parse_ipc_op_response(response.stringify())
  let error : IpcCommandError = @json.from_json(decoded.body)
  assert_eq(error.code, "invalid_payload")
  assert_eq(error.message, "invalid command payload")
  assert_eq(error.detail, Some("field name is required"))
  for
    body in [
      Json("legacy error"),
      { "code": "", "message": "error" },
      { "code": "handler_failed" },
    ] {
    let invalid = IpcOpResponse::{
      version: protocol_version(),
      id: "invalid",
      status: 1,
      body,
    }
    assert_eq(
      expect_ipc_error(() => invalid.validate()),
      IpcError::InvalidErrorResponseBody,
    )
  }
  let legacy = IpcOpResponse::{
    version: 1,
    id: "legacy",
    status: 1,
    body: Json("old error"),
  }
  assert_eq(
    expect_ipc_error(() => legacy.validate()),
    IpcError::UnsupportedVersion(
      scope="protocol",
      actual=1,
      supported=protocol_version(),
    ),
  )
}
