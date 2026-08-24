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
pub extend IpcOpRequest with Eq::{not_equal, equal}

///|
pub extend IpcOpRequest with Debug::{to_repr}

///|
pub extend IpcOpRequest with ToJson::{to_json}

///|
pub extend IpcOpRequest with FromJson::{from_json}

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
pub extend IpcOpResponse with Eq::{not_equal, equal}

///|
pub extend IpcOpResponse with Debug::{to_repr}

///|
pub extend IpcOpResponse with ToJson::{to_json}

///|
pub extend IpcOpResponse with FromJson::{from_json}

///|
/// One extension event sent from the user process to JavaScript.
pub(all) struct IpcExtensionEvent {
  version : Int
  extension_namespace : String
  event_name : String
  payload : Json
} derive(ToJson, FromJson, Eq, Debug)

///|
pub extend IpcExtensionEvent with Eq::{not_equal, equal}

///|
pub extend IpcExtensionEvent with Debug::{to_repr}

///|
pub extend IpcExtensionEvent with ToJson::{to_json}

///|
pub extend IpcExtensionEvent with FromJson::{from_json}

///|
/// One JavaScript-facing API exposed for a remote extension namespace.
pub(all) struct IpcExtensionApi {
  api_name : String
} derive(ToJson, FromJson, Eq, Debug)

///|
pub extend IpcExtensionApi with Eq::{not_equal, equal}

///|
pub extend IpcExtensionApi with Debug::{to_repr}

///|
pub extend IpcExtensionApi with ToJson::{to_json}

///|
pub extend IpcExtensionApi with FromJson::{from_json}

///|
/// JavaScript bridge metadata for one remote extension.
pub(all) struct IpcExtensionDescriptor {
  id : String
  js_namespace : String
  apis : Array[IpcExtensionApi]
  scripts : Array[String]
} derive(ToJson, FromJson, Eq, Debug)

///|
pub extend IpcExtensionDescriptor with Eq::{not_equal, equal}

///|
pub extend IpcExtensionDescriptor with Debug::{to_repr}

///|
pub extend IpcExtensionDescriptor with ToJson::{to_json}

///|
pub extend IpcExtensionDescriptor with FromJson::{from_json}

///|
/// Creates one operation request frame.
pub fn IpcOpRequest::new(
  id : String,
  name : String,
  payload : Json,
) -> IpcOpRequest {
  IpcOpRequest::{ version: ipc_protocol_version, id, name, payload, }
}

///|
/// Creates one successful operation response frame.
pub fn IpcOpResponse::ok(id : String, body : Json) -> IpcOpResponse {
  IpcOpResponse::{ version: ipc_protocol_version, id, status: 0, body, }
}

///|
/// Creates one failed operation response frame.
pub fn IpcOpResponse::err(id : String, message : String) -> IpcOpResponse {
  IpcOpResponse::{
    version: ipc_protocol_version,
    id,
    status: 1,
    body: Json(message),
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
