///|
/// Errors raised while decoding raw JSON messages from a CDP WebSocket.
///
/// These errors describe envelope-level decoding only. They do not validate
/// whether a method exists in the CDP schema or whether params/results match a
/// domain-specific command; use the schema helpers in `schema_command.mbt` for
/// that layer.
pub(all) suberror ProtocolDecodeError {
  ExpectedObject
  MissingField(String)
  InvalidField(String)
} derive(Eq, ToJson, Debug)

///|
/// Outgoing CDP command envelope.
///
/// `method_name` is the fully-qualified CDP method such as
/// `Runtime.evaluate`. `session_id` is present for target-scoped commands sent
/// through a flattened session.
///
/// `params = None` omits the `params` field from the wire JSON. Use an empty
/// JSON object when the caller needs to send an explicit empty params object.
pub(all) struct CdpCommandMessage {
  id : Int
  method_name : String
  params : Json?
  session_id : String?
} derive(Eq, ToJson, Debug)

///|
/// Error object returned by a failed CDP command response.
///
/// `code` and `message` are required by CDP. `data` is browser/domain-specific
/// and is preserved without interpretation.
pub(all) struct CdpError {
  code : Int
  message : String
  data : Json?
} derive(Eq, ToJson, Debug)

///|
/// Incoming CDP command response envelope.
///
/// A response always has an `id`, may contain `result`, and may contain `error`.
/// Target session responses include `session_id`.
///
/// Successful commands usually contain `result`, but commands with no modeled
/// return fields may omit it. Error responses keep the browser-provided
/// `CdpError` and may omit `result`.
pub(all) struct CdpResponseMessage {
  id : Int
  result : Json?
  error : CdpError?
  session_id : String?
} derive(Eq, ToJson, Debug)

///|
/// Incoming CDP event envelope.
///
/// Events do not carry a command id. Target session events include `session_id`.
/// `params` is optional because some CDP events have no payload.
pub(all) struct CdpEventMessage {
  method_name : String
  params : Json?
  session_id : String?
} derive(Eq, ToJson, Debug)

///|
/// Parsed incoming CDP WebSocket message.
///
/// CDP distinguishes responses and events by the presence of an `id` field.
/// This enum keeps that split explicit for clients that multiplex command waits
/// and event reads on the same WebSocket.
pub(all) enum CdpIncomingMessage {
  Response(CdpResponseMessage)
  Event(CdpEventMessage)
} derive(Eq, ToJson, Debug)

///|
/// Build a CDP command envelope.
///
/// Use `to_wire_json` or `stringify` to serialize the command before sending it
/// to a WebSocket. Prefer `cdp_schema_command` when the command should be
/// validated against the bundled protocol schema.
///
/// # Example
/// ```mbt nocheck
/// let command = cdp_command(id=1, method_name="Browser.getVersion")
/// assert_eq(command.stringify(), "{\"id\":1,\"method\":\"Browser.getVersion\"}")
/// ```
pub fn cdp_command(
  id~ : Int,
  method_name~ : String,
  params? : Json,
  session_id? : String,
) -> CdpCommandMessage {
  { id, method_name, params, session_id }
}

///|
/// Convert a command envelope to CDP wire JSON.
///
/// Field names are converted to CDP's wire format: `method_name` becomes
/// `method`, and `session_id` becomes `sessionId`.
pub fn CdpCommandMessage::to_wire_json(self : CdpCommandMessage) -> Json {
  let fields : Map[String, Json] = {
    "id": Json::number(self.id.to_double()),
    "method": Json::string(self.method_name),
  }
  if self.params is Some(params) {
    fields["params"] = params
  }
  if self.session_id is Some(session_id) {
    fields["sessionId"] = Json::string(session_id)
  }
  Json::object(fields)
}

///|
/// Serialize a command envelope to a JSON string for WebSocket transport.
///
/// This is a thin wrapper around `to_wire_json().stringify()`.
pub fn CdpCommandMessage::stringify(self : CdpCommandMessage) -> String {
  self.to_wire_json().stringify()
}

///|
/// Parse one incoming CDP JSON message as either a response or an event.
///
/// Messages with an `id` field are decoded as responses; messages without `id`
/// are decoded as events and must contain a string `method` field.
///
/// The parser preserves unmodeled `result`, `params`, `error.data`, and
/// top-level session information as JSON. It rejects only malformed envelope
/// fields needed by the transport layer.
pub fn parse_cdp_incoming(
  json : Json,
) -> CdpIncomingMessage raise ProtocolDecodeError {
  guard json is Object(fields) else { raise ExpectedObject }
  match fields.get("id") {
    Some(id_json) => Response(parse_response(fields, id_json))
    None => Event(parse_event(fields))
  }
}

///|
// Decode a response object after the caller has found its `id`.
fn parse_response(
  fields : Map[String, Json],
  id_json : Json,
) -> CdpResponseMessage raise ProtocolDecodeError {
  let id = json_int(id_json, "id")
  let result = fields.get("result")
  let error = match fields.get("error") {
    Some(error_json) => Some(parse_error(error_json))
    None => None
  }
  let session_id = optional_string(fields, "sessionId")
  { id, result, error, session_id }
}

///|
// Decode an event object from message fields.
fn parse_event(
  fields : Map[String, Json],
) -> CdpEventMessage raise ProtocolDecodeError {
  let method_name = required_string(fields, "method")
  let params = fields.get("params")
  let session_id = optional_string(fields, "sessionId")
  { method_name, params, session_id }
}

///|
// Decode a CDP error object from a failed response.
fn parse_error(json : Json) -> CdpError raise ProtocolDecodeError {
  guard json is Object(fields) else { raise InvalidField("error") }
  let code = match fields.get("code") {
    Some(value) => json_int(value, "error.code")
    None => raise MissingField("error.code")
  }
  let message = required_string(fields, "message")
  let data = fields.get("data")
  { code, message, data }
}

///|
// Read a required string field from a JSON object.
fn required_string(
  fields : Map[String, Json],
  name : String,
) -> String raise ProtocolDecodeError {
  match fields.get(name) {
    Some(String(value)) => value
    Some(_) => raise InvalidField(name)
    None => raise MissingField(name)
  }
}

///|
// Read an optional string field from a JSON object.
fn optional_string(
  fields : Map[String, Json],
  name : String,
) -> String? raise ProtocolDecodeError {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    Some(_) => raise InvalidField(name)
    None => None
  }
}

///|
// Decode a JSON number as an exact integer.
fn json_int(json : Json, name : String) -> Int raise ProtocolDecodeError {
  match json {
    Number(value, ..) => {
      let int = value.to_int()
      if int.to_double() == value {
        int
      } else {
        raise InvalidField(name)
      }
    }
    _ => raise InvalidField(name)
  }
}
