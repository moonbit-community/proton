///|
let ipc_protocol_version = 1

///|
/// Returns the protocol version used in all IPC envelopes and payloads.
pub fn protocol_version() -> Int {
  ipc_protocol_version
}

///|
/// One operation invocation sent from the JavaScript bridge to the user process.
pub(all) struct IpcOpRequest {
  version : Int
  id : String
  name : String
  payload : Json
} derive(ToJson, FromJson, Eq, Debug)

///|
/// One operation completion sent from the user process back to JavaScript.
///
/// `status == 0` means success. Any non-zero status means `body` contains a JSON
/// string error message suitable for rejecting the JavaScript promise.
pub(all) struct IpcOpResponse {
  version : Int
  id : String
  status : Int
  body : Json
} derive(ToJson, FromJson, Eq, Debug)

///|
/// One extension event sent from the user process to JavaScript.
pub(all) struct IpcExtensionEvent {
  version : Int
  extension_namespace : String
  event_name : String
  payload : Json
} derive(ToJson, FromJson, Eq, Debug)

///|
/// One JavaScript-facing API exposed for a remote extension namespace.
pub(all) struct IpcExtensionApi {
  api_name : String
} derive(ToJson, FromJson, Eq, Debug)

///|
/// JavaScript bridge metadata for one remote extension.
pub(all) struct IpcExtensionDescriptor {
  id : String
  js_namespace : String
  apis : Array[IpcExtensionApi]
  scripts : Array[String]
} derive(ToJson, FromJson, Eq, Debug)

///|
/// One protocol envelope exchanged by a concrete IPC transport.
pub(all) struct IpcFrame {
  version : Int
  kind : String
  payload : Json
} derive(ToJson, FromJson, Eq, Debug)

///|
/// Creates one operation request frame.
pub fn IpcOpRequest::new(
  id : String,
  name : String,
  payload : Json,
) -> IpcOpRequest {
  IpcOpRequest::{ version: ipc_protocol_version, id, name, payload }
}

///|
/// Creates one successful operation response frame.
pub fn IpcOpResponse::ok(id : String, body : Json) -> IpcOpResponse {
  IpcOpResponse::{ version: ipc_protocol_version, id, status: 0, body }
}

///|
/// Creates one failed operation response frame.
pub fn IpcOpResponse::err(id : String, message : String) -> IpcOpResponse {
  IpcOpResponse::{
    version: ipc_protocol_version,
    id,
    status: 1,
    body: Json::string(message),
  }
}

///|
/// Returns whether this response represents success.
pub fn IpcOpResponse::is_ok(self : IpcOpResponse) -> Bool {
  self.status == 0
}

///|
/// Serializes an operation request as one JSON IPC payload.
pub fn IpcOpRequest::stringify(self : IpcOpRequest) -> String {
  ToJson::to_json(self).stringify()
}

///|
/// Serializes an operation response as one JSON IPC payload.
pub fn IpcOpResponse::stringify(self : IpcOpResponse) -> String {
  ToJson::to_json(self).stringify()
}

///|
/// Serializes one transport frame.
pub fn IpcFrame::stringify(self : IpcFrame) -> String {
  ToJson::to_json(self).stringify()
}

///|
/// Parses one JSON IPC operation request.
pub fn parse_ipc_op_request(raw : String) -> IpcOpRequest raise IpcError {
  let request : IpcOpRequest = @json.from_json(parse_json(raw)) catch {
    err => raise InvalidPayload(kind="request", detail=err.to_string())
  }
  validate_ipc_op_request(request)
}

///|
/// Parses one JSON IPC operation response.
pub fn parse_ipc_op_response(raw : String) -> IpcOpResponse raise IpcError {
  let response : IpcOpResponse = @json.from_json(parse_json(raw)) catch {
    err => raise InvalidPayload(kind="response", detail=err.to_string())
  }
  validate_ipc_op_response(response)
}

///|
/// Parses one JSON IPC transport frame.
pub fn parse_ipc_frame(raw : String) -> IpcFrame raise IpcError {
  let frame : IpcFrame = @json.from_json(parse_json(raw)) catch {
    err => raise InvalidPayload(kind="frame", detail=err.to_string())
  }
  validate_ipc_frame(frame)
}

///|
/// Creates one extension event IPC frame.
pub fn IpcExtensionEvent::new(
  extension_namespace : String,
  event_name : String,
  payload : Json,
) -> IpcExtensionEvent {
  IpcExtensionEvent::{
    version: ipc_protocol_version,
    extension_namespace,
    event_name,
    payload,
  }
}

///|
/// Creates one remote extension API descriptor.
pub fn IpcExtensionApi::new(api_name : String) -> IpcExtensionApi {
  IpcExtensionApi::{ api_name, }
}

///|
/// Creates one remote extension bridge descriptor.
pub fn IpcExtensionDescriptor::new(
  id : String,
  js_namespace : String,
  apis : Array[IpcExtensionApi],
  scripts? : Array[String] = [],
) -> IpcExtensionDescriptor {
  IpcExtensionDescriptor::{
    id,
    js_namespace,
    apis: apis.map(fn(api) { api }),
    scripts: scripts.map(fn(script) { script }),
  }
}

///|
/// Wraps an operation request in a transport frame.
pub fn IpcFrame::request(request : IpcOpRequest) -> IpcFrame {
  IpcFrame::{
    version: ipc_protocol_version,
    kind: "request",
    payload: ToJson::to_json(request),
  }
}

///|
/// Wraps an operation response in a transport frame.
pub fn IpcFrame::response(response : IpcOpResponse) -> IpcFrame {
  IpcFrame::{
    version: ipc_protocol_version,
    kind: "response",
    payload: ToJson::to_json(response),
  }
}

///|
/// Wraps an extension event in a transport frame.
pub fn IpcFrame::event(event : IpcExtensionEvent) -> IpcFrame {
  IpcFrame::{
    version: ipc_protocol_version,
    kind: "event",
    payload: ToJson::to_json(event),
  }
}

///|
/// Validates one decoded operation request.
pub fn IpcOpRequest::validate(
  self : IpcOpRequest,
) -> IpcOpRequest raise IpcError {
  validate_ipc_op_request(self)
}

///|
/// Validates one decoded operation response.
pub fn IpcOpResponse::validate(
  self : IpcOpResponse,
) -> IpcOpResponse raise IpcError {
  validate_ipc_op_response(self)
}

///|
/// Validates one decoded extension event.
pub fn IpcExtensionEvent::validate(
  self : IpcExtensionEvent,
) -> IpcExtensionEvent raise IpcError {
  validate_ipc_extension_event(self)
}

///|
/// Validates one decoded transport frame envelope.
pub fn IpcFrame::validate(self : IpcFrame) -> IpcFrame raise IpcError {
  validate_ipc_frame(self)
}

///|
/// Decodes this frame as an operation request.
pub fn IpcFrame::as_request(self : IpcFrame) -> IpcOpRequest raise IpcError {
  let _ = self.validate()
  guard self.kind == "request" else {
    raise UnexpectedFrameKind(expected="request", actual=self.kind)
  }
  let request : IpcOpRequest = @json.from_json(self.payload) catch {
    err => raise InvalidPayload(kind="request", detail=err.to_string())
  }
  validate_ipc_op_request(request)
}

///|
/// Decodes this frame as an operation response.
pub fn IpcFrame::as_response(self : IpcFrame) -> IpcOpResponse raise IpcError {
  let _ = self.validate()
  guard self.kind == "response" else {
    raise UnexpectedFrameKind(expected="response", actual=self.kind)
  }
  let response : IpcOpResponse = @json.from_json(self.payload) catch {
    err => raise InvalidPayload(kind="response", detail=err.to_string())
  }
  validate_ipc_op_response(response)
}

///|
/// Decodes this frame as an extension event.
pub fn IpcFrame::as_event(self : IpcFrame) -> IpcExtensionEvent raise IpcError {
  let _ = self.validate()
  guard self.kind == "event" else {
    raise UnexpectedFrameKind(expected="event", actual=self.kind)
  }
  let event : IpcExtensionEvent = @json.from_json(self.payload) catch {
    err => raise InvalidPayload(kind="event", detail=err.to_string())
  }
  validate_ipc_extension_event(event)
}

///|
fn parse_json(raw : String) -> Json raise IpcError {
  @json.parse(raw) catch {
    err => raise MalformedJson(detail=err.to_string())
  }
}

///|
fn validate_ipc_op_request(
  request : IpcOpRequest,
) -> IpcOpRequest raise IpcError {
  guard request.version == ipc_protocol_version else {
    raise UnsupportedVersion(
      scope="protocol",
      actual=request.version,
      supported=ipc_protocol_version,
    )
  }
  guard request.id.trim().to_owned() != "" else {
    raise EmptyField(path="IPC request id")
  }
  guard request.name.trim().to_owned() != "" else {
    raise EmptyField(path="IPC request name")
  }
  request
}

///|
fn validate_ipc_op_response(
  response : IpcOpResponse,
) -> IpcOpResponse raise IpcError {
  guard response.version == ipc_protocol_version else {
    raise UnsupportedVersion(
      scope="protocol",
      actual=response.version,
      supported=ipc_protocol_version,
    )
  }
  guard response.id.trim().to_owned() != "" else {
    raise EmptyField(path="IPC response id")
  }
  if response.status != 0 {
    guard response.body is String(_) else { raise InvalidErrorResponseBody }
  }
  response
}

///|
fn validate_ipc_extension_event(
  event : IpcExtensionEvent,
) -> IpcExtensionEvent raise IpcError {
  guard event.version == ipc_protocol_version else {
    raise UnsupportedVersion(
      scope="event",
      actual=event.version,
      supported=ipc_protocol_version,
    )
  }
  guard event.extension_namespace.trim().to_owned() != "" else {
    raise EmptyField(path="IPC event extension namespace")
  }
  guard event.event_name.trim().to_owned() != "" else {
    raise EmptyField(path="IPC event name")
  }
  event
}

///|
fn validate_ipc_frame(frame : IpcFrame) -> IpcFrame raise IpcError {
  guard frame.version == ipc_protocol_version else {
    raise UnsupportedVersion(
      scope="frame",
      actual=frame.version,
      supported=ipc_protocol_version,
    )
  }
  guard frame.kind == "request" ||
    frame.kind == "response" ||
    frame.kind == "event" else {
    raise UnsupportedFrameKind(kind=frame.kind)
  }
  frame
}
