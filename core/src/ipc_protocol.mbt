///|
let ipc_protocol_version = 1

///|
/// One operation invocation sent from the webview process to the MBT process.
pub(all) struct IpcOpRequest {
  version : Int
  id : String
  name : String
  payload : Json
} derive(ToJson, FromJson, Eq, Debug)

///|
/// One operation completion sent from the MBT process back to the webview process.
///
/// `status == 0` means success. Any non-zero status means `body` contains a JSON
/// string error message suitable for `webview_return`.
pub(all) struct IpcOpResponse {
  version : Int
  id : String
  status : Int
  body : Json
} derive(ToJson, FromJson, Eq, Debug)

///|
/// One extension event sent from the MBT process to a webview process.
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
/// JavaScript bridge metadata installed by the webview process for one remote extension.
pub(all) struct IpcExtensionDescriptor {
  id : String
  js_namespace : String
  apis : Array[IpcExtensionApi]
  scripts : Array[String]
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
/// Parses one JSON IPC operation request.
pub fn parse_ipc_op_request(raw : String) -> Result[IpcOpRequest, String] {
  let parsed : Result[Json, _] = try? @json.parse(raw)
  parsed
  .map_err(fn(err) { err.to_string() })
  .bind(fn(json) {
    let request : Result[IpcOpRequest, _] = try? @json.from_json(json)
    request.map_err(fn(err) { err.to_string() }).bind(validate_ipc_op_request)
  })
}

///|
/// Parses one JSON IPC operation response.
pub fn parse_ipc_op_response(raw : String) -> Result[IpcOpResponse, String] {
  let parsed : Result[Json, _] = try? @json.parse(raw)
  parsed
  .map_err(fn(err) { err.to_string() })
  .bind(fn(json) {
    let response : Result[IpcOpResponse, _] = try? @json.from_json(json)
    response.map_err(fn(err) { err.to_string() }).bind(validate_ipc_op_response)
  })
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
  IpcExtensionDescriptor::{ id, js_namespace, apis, scripts }
}

///|
fn validate_ipc_op_request(
  request : IpcOpRequest,
) -> Result[IpcOpRequest, String] {
  guard request.version == ipc_protocol_version else {
    return Err(
      "Unsupported IPC protocol version: " + request.version.to_string(),
    )
  }
  guard request.id.trim().to_owned() != "" else {
    return Err("IPC request id must not be empty")
  }
  guard request.name.trim().to_owned() != "" else {
    return Err("IPC request name must not be empty")
  }
  Ok(request)
}

///|
fn validate_ipc_op_response(
  response : IpcOpResponse,
) -> Result[IpcOpResponse, String] {
  guard response.version == ipc_protocol_version else {
    return Err(
      "Unsupported IPC protocol version: " + response.version.to_string(),
    )
  }
  guard response.id.trim().to_owned() != "" else {
    return Err("IPC response id must not be empty")
  }
  Ok(response)
}
