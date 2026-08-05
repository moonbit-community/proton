///|
/// Errors raised by CDP response helpers and minimal target helpers.
///
/// These errors describe local validation or CDP error responses. They do not
/// replace `CdpResponseMessage.error`; use `send_command` directly when callers
/// want to inspect raw CDP errors without raising.
///
/// `CommandFailed` wraps the browser-provided CDP error code and message.
/// `MissingField` and `InvalidField` indicate this library could not convert a
/// successful response into the requested helper type. `WaitTimeout` is used by
/// response waits when a command id does not complete in time.
pub(all) suberror BrowserError {
  CommandFailed(Int, String)
  MissingField(String)
  InvalidField(String)
  WaitTimeout(String)
} derive(Eq, ToJson, Debug)

///|
/// Basic target metadata returned by `Target.getTargets`.
///
/// `target_id` is the value used by `Target.attachToTarget` and
/// `Target.createTarget` results. `target_type`, `title`, `url`, and
/// `attached` mirror Chrome's `targetInfo` object. `browser_context_id` is
/// present only for browsers/targets that report it.
///
/// Example:
/// ```
/// // let targets = client.get_targets()
/// // println(targets.length().to_string())
/// ```
pub(all) struct CdpTargetInfo {
  target_id : String
  target_type : String
  title : String
  url : String
  attached : Bool
  browser_context_id : String?
} derive(Eq, ToJson, Debug)

///|
/// Lists targets using the browser-level `Target.getTargets` command.
///
/// This method requires a browser WebSocket connection, not a page WebSocket.
/// It validates the response shape and converts each `targetInfo` object to
/// `CdpTargetInfo`.
///
/// Use this for a live browser-side target list. It is different from
/// `attached_targets`, which reports only targets attached through this client
/// and observed through flattened session events.
///
/// Example:
/// ```
/// // let client = connect_cdp_browser_target(parse_cdp_target("9222"))
/// // let targets = client.get_targets()
/// ```
pub async fn CdpClient::get_targets(self : CdpClient) -> Array[CdpTargetInfo] {
  let response = self.send_schema_command("Target.getTargets")
  let result = response_result(response)
  parse_target_infos(result)
}

///|
// Converts a `Target.getTargets` result object into target metadata.
fn parse_target_infos(
  result : Map[String, Json],
) -> Array[CdpTargetInfo] raise BrowserError {
  guard required_json(result, "targetInfos") is Array(targets) else {
    raise InvalidField("targetInfos")
  }
  targets.map(parse_target_info)
}

///|
/// Creates a new browser target and returns its `targetId`.
///
/// The default URL is `about:blank`. Pass `browser_context_id` to create the
/// target in an existing context, or `new_window=true` when the browser supports
/// window creation through CDP.
///
/// The returned target is not automatically attached. Call `attach_to_target`
/// and send target-scoped commands with the returned `session_id`, or discover a
/// page WebSocket separately when direct page connections are preferred.
///
/// Example:
/// ```
/// // let target_id = client.create_target(url="about:blank")
/// ```
pub async fn CdpClient::create_target(
  self : CdpClient,
  url? : String = "about:blank",
  browser_context_id? : String,
  new_window? : Bool = false,
) -> String {
  let params : Map[String, Json] = { "url": Json::string(url) }
  if browser_context_id is Some(browser_context_id) {
    params["browserContextId"] = Json::string(browser_context_id)
  }
  if new_window {
    params["newWindow"] = Json::boolean(true)
  }
  let response = self.send_schema_command(
    "Target.createTarget",
    params=Json::object(params),
  )
  let result = response_result(response)
  required_string(result, "targetId")
}

///|
/// Attaches to an existing target and returns the CDP `sessionId`.
///
/// By default the method requests flattened session mode, which is the safest
/// mode for clients that multiplex browser and target commands over one
/// browser WebSocket.
///
/// In flattened mode, pass the returned session id to `send_schema_command`,
/// `send_cdp_command`, or typed command messages so Chrome routes the command to
/// the attached target.
///
/// Example:
/// ```
/// // let session_id = client.attach_to_target(target_id)
/// ```
pub async fn CdpClient::attach_to_target(
  self : CdpClient,
  target_id : String,
  flatten? : Bool = true,
) -> String {
  let response = self.send_schema_command("Target.attachToTarget", params={
    "targetId": target_id,
    "flatten": flatten,
  })
  let result = response_result(response)
  required_string(result, "sessionId")
}

///|
/// Converts one `targetInfo` JSON value to `CdpTargetInfo`.
fn parse_target_info(value : Json) -> CdpTargetInfo raise BrowserError {
  guard value is Object(fields) else { raise InvalidField("targetInfos[]") }
  {
    target_id: required_string(fields, "targetId"),
    target_type: required_string(fields, "type"),
    title: required_string(fields, "title"),
    url: required_string(fields, "url"),
    attached: optional_bool(fields, "attached").unwrap_or(false),
    browser_context_id: optional_string(fields, "browserContextId"),
  }
}

///|
/// Returns the object result from a successful CDP response.
fn response_result(
  response : @protocol.CdpResponseMessage,
) -> Map[String, Json] raise BrowserError {
  if response.error is Some(err) {
    raise CommandFailed(err.code, err.message)
  }
  match response.result {
    Some(Object(result)) => result
    Some(_) => raise InvalidField("result")
    None => raise MissingField("result")
  }
}

///|
/// Returns the raw JSON result object from a CDP response.
///
/// If the response is a CDP error, this raises `BrowserError::CommandFailed`.
/// If the response has no result, it returns an empty object. This helper is
/// useful before feeding a response into generated result decoders.
///
/// The helper does not validate the result shape. Use schema-aware send helpers
/// before calling it when callers need bundled-schema validation.
///
/// Example:
/// ```
/// // let response = client.send_schema_command("Browser.getVersion")
/// // let result = cdp_response_result_json(response)
/// ```
pub fn cdp_response_result_json(
  response : @protocol.CdpResponseMessage,
) -> Json raise BrowserError {
  if response.error is Some(err) {
    raise CommandFailed(err.code, err.message)
  }
  match response.result {
    Some(result) => result
    None => Json::object({})
  }
}

///|
/// Reads a required JSON field.
fn required_json(
  fields : Map[String, Json],
  name : String,
) -> Json raise BrowserError {
  match fields.get(name) {
    Some(value) => value
    None => raise MissingField(name)
  }
}

///|
/// Reads a required string field.
fn required_string(
  fields : Map[String, Json],
  name : String,
) -> String raise BrowserError {
  match fields.get(name) {
    Some(String(value)) => value
    Some(_) => raise InvalidField(name)
    None => raise MissingField(name)
  }
}

///|
/// Reads an optional string field.
fn optional_string(
  fields : Map[String, Json],
  name : String,
) -> String? raise BrowserError {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    Some(_) => raise InvalidField(name)
    None => None
  }
}

///|
/// Reads an optional boolean field.
fn optional_bool(
  fields : Map[String, Json],
  name : String,
) -> Bool? raise BrowserError {
  match fields.get(name) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(_) => raise InvalidField(name)
    None => None
  }
}

///|
/// Validates a positive duration in milliseconds.
fn checked_duration(value : Int, name : String) -> Int raise BrowserError {
  if value > 0 {
    value
  } else {
    raise InvalidField(name)
  }
}
