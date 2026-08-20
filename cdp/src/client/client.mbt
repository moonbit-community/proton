///|
async fn[T, E : Error] try_result_client_client(
  f : async () -> T raise E,
) -> Result[T, E] {
  try f() catch {
    e => Err(e)
  } noraise {
    value => Ok(value)
  }
}

///|
/// WebSocket client for Chrome DevTools Protocol.
///
/// `CdpClient` tracks in-flight command ids, dispatches responses and events
/// from one reader task, and exposes raw plus schema-aware send helpers. Create it from a
/// direct WebSocket URL with `CdpClient::connect`, or from a discovery target
/// with `connect_cdp_target` / `connect_cdp_browser_target`.
///
/// The client is intentionally a thin CDP transport. It does not own browser
/// lifecycle, retry commands, or interpret domain semantics beyond lightweight
/// schema validation. Its reader belongs to the caller-provided task group, so
/// connection lifetime remains structurally scoped.
///
/// State retained by the client is diagnostic and convenience state:
///
/// - `last_cdp_request`, `last_cdp_response`, and `last_cdp_event` expose the
///   most recent traffic observed by this client.
/// - `attached_targets` mirrors flattened target attach/detach events seen on
///   this connection; it is not a full browser target registry.
///
/// Example:
/// ```
/// // let client = CdpClient::connect(tasks, "ws://127.0.0.1:9222/devtools/browser/id")
/// // defer client.close()
/// ```
pub struct CdpClient {
  priv ws : @websocket.Conn
  priv mut next_id : Int
  priv mut next_event_handler_id : Int
  priv mut next_close_handler_id : Int
  priv pending_commands : Map[Int, CdpPendingCommand]
  priv command_contexts : Map[Int, CdpCommandContext]
  priv mut closed : Bool
  priv event_changed : @async.CondVar
  priv mut last_command_failure : CdpCommandFailure?
  priv cdp_event_handlers : Array[CdpEventHandler]
  priv close_handlers : Array[CdpCloseHandler]
  priv mut last_cdp_request : @protocol.CdpCommandMessage?
  priv mut last_cdp_response : @protocol.CdpResponseMessage?
  priv mut last_cdp_event : @protocol.CdpEventMessage?
  priv attached_targets : Map[String, CdpAttachedTarget]
}

///|
priv enum CdpPendingCommandState {
  Waiting
  Completed(@protocol.CdpResponseMessage)
  ConnectionClosed
}

///|
priv struct CdpPendingCommand {
  mut state : CdpPendingCommandState
  changed : @async.CondVar
}

///|
/// Tracks the method and session for one in-flight command.
struct CdpCommandContext {
  method_name : String
  session_id : String?
}

///|
/// Stores one event subscription callback.
struct CdpEventHandler {
  id : Int
  method_name : String?
  session_id : String?
  handler : (@protocol.CdpEventMessage) -> Unit
}

///|
struct CdpCloseHandler {
  id : Int
  handler : () -> Unit
}

///|
/// Details about the last CDP command that returned an error response.
///
/// `method_name` and `session_id` are copied from the in-flight command context
/// when available. If the response was not associated with a tracked command,
/// `method_name` is empty and `session_id` falls back to the response envelope.
/// `code`, `message`, and `data` are the browser-provided CDP error object.
///
/// Example:
/// ```
/// // guard client.last_command_failure() is Some(failure) else { return }
/// // println(failure.message)
/// ```
pub(all) struct CdpCommandFailure {
  id : Int
  method_name : String
  session_id : String?
  code : Int
  message : String
  data : Json?
} derive(Eq, ToJson, Debug)

///|
pub extend CdpCommandFailure with Eq::{not_equal, equal}

///|
pub extend CdpCommandFailure with Debug::{to_repr}

///|
pub extend CdpCommandFailure with ToJson::{to_json}

///|
/// Metadata for a target currently attached through a flattened CDP session.
///
/// The client updates this cache from `Target.attachedToTarget`,
/// `Target.detachedFromTarget`, and `Inspector.detached` events.
///
/// `session_id` is the flattened CDP session id used when sending target-scoped
/// commands. `target_id`, `target_type`, `title`, and `url` come from the
/// event's `targetInfo` payload. `attached` and `waiting_for_debugger` reflect
/// Chrome's event fields at the time the attach event was observed.
pub(all) struct CdpAttachedTarget {
  session_id : String
  target_id : String
  target_type : String
  title : String
  url : String
  attached : Bool
  browser_context_id : String?
  waiting_for_debugger : Bool
} derive(Eq, ToJson, Debug)

///|
pub extend CdpAttachedTarget with Eq::{not_equal, equal}

///|
pub extend CdpAttachedTarget with Debug::{to_repr}

///|
pub extend CdpAttachedTarget with ToJson::{to_json}

///|
/// Errors raised while opening a CDP WebSocket.
///
/// `ConnectionTimeout` means the connection attempt did not finish before the
/// configured timeout. `WebSocketHandshakeFailed` means the socket attempt
/// completed but the endpoint rejected or failed the WebSocket handshake.
pub(all) suberror CdpConnectionError {
  ConnectionTimeout(String, Int)
  WebSocketHandshakeFailed(String, String)
} derive(Eq, ToJson, Debug)

///|
pub extend CdpConnectionError with Eq::{not_equal, equal}

///|
pub extend CdpConnectionError with Debug::{to_repr}

///|
pub extend CdpConnectionError with ToJson::{to_json}

///|
/// Structured diagnostic data for `CdpConnectionError`.
pub(all) struct CdpConnectionErrorDiagnostic {
  kind : String
  web_socket_url : String
  timeout_ms : Int?
  reason : String?
  path : String
  message : String
} derive(Eq, ToJson, Debug)

///|
pub extend CdpConnectionErrorDiagnostic with Eq::{not_equal, equal}

///|
pub extend CdpConnectionErrorDiagnostic with Debug::{to_repr}

///|
pub extend CdpConnectionErrorDiagnostic with ToJson::{to_json}

///|
/// Converts a connection error to structured diagnostic data.
///
/// Example:
/// ```
/// // let diagnostic = err.diagnostic()
/// // println(diagnostic.message)
/// ```
pub fn CdpConnectionError::diagnostic(
  self : CdpConnectionError,
) -> CdpConnectionErrorDiagnostic {
  {
    kind: self.kind(),
    web_socket_url: self.web_socket_url(),
    timeout_ms: self.timeout_ms(),
    reason: self.reason(),
    path: self.path(),
    message: self.message(),
  }
}

///|
/// Returns a stable machine-readable error kind.
pub fn CdpConnectionError::kind(self : CdpConnectionError) -> String {
  match self {
    ConnectionTimeout(_, _) => "connection_timeout"
    WebSocketHandshakeFailed(_, _) => "websocket_handshake_failed"
  }
}

///|
/// Returns the WebSocket URL associated with the connection error.
pub fn CdpConnectionError::web_socket_url(self : CdpConnectionError) -> String {
  match self {
    ConnectionTimeout(web_socket_url, _)
    | WebSocketHandshakeFailed(web_socket_url, _) => web_socket_url
  }
}

///|
/// Returns the timeout used for timeout errors.
pub fn CdpConnectionError::timeout_ms(self : CdpConnectionError) -> Int? {
  match self {
    ConnectionTimeout(_, timeout_ms) => Some(timeout_ms)
    WebSocketHandshakeFailed(_, _) => None
  }
}

///|
/// Returns the low-level reason for handshake failures.
pub fn CdpConnectionError::reason(self : CdpConnectionError) -> String? {
  match self {
    WebSocketHandshakeFailed(_, reason) => Some(reason)
    ConnectionTimeout(_, _) => None
  }
}

///|
/// Returns a stable dotted diagnostic path.
pub fn CdpConnectionError::path(self : CdpConnectionError) -> String {
  match self {
    ConnectionTimeout(_, _) => "connection.websocket.timeout"
    WebSocketHandshakeFailed(_, _) => "connection.websocket.handshake"
  }
}

///|
/// Returns a human-readable connection error message.
pub fn CdpConnectionError::message(self : CdpConnectionError) -> String {
  match self {
    ConnectionTimeout(web_socket_url, timeout_ms) =>
      "timed out after \{timeout_ms}ms connecting to \{web_socket_url}"
    WebSocketHandshakeFailed(web_socket_url, reason) =>
      "websocket handshake failed for \{web_socket_url}: \{reason}"
  }
}

///|
/// Opens a CDP WebSocket connection.
///
/// This function expects a direct `ws://` or `wss://` DevTools URL. Use
/// `connect_cdp_target` if you have a port or HTTP discovery endpoint instead.
/// The connection starts with empty event, response, and attached-target state.
///
/// Example:
/// ```
/// // let client = CdpClient::connect(tasks, "ws://127.0.0.1:9222/devtools/browser/id")
/// ```
pub async fn[X] CdpClient::connect(
  tasks : @async.TaskGroup[X],
  web_socket_url : String,
) -> CdpClient {
  CdpClient::from_websocket(tasks, @websocket.connect(web_socket_url))
}

///|
/// Opens a CDP WebSocket connection with a timeout.
///
/// Raises `CdpConnectionError::ConnectionTimeout` when no connection is
/// established within `timeout_ms`, and `WebSocketHandshakeFailed` for handshake
/// failures.
///
/// `timeout_ms` must be positive. The timeout covers the WebSocket connection
/// attempt only; command and event waits have their own timeout parameters.
///
/// Example:
/// ```
/// // let client = CdpClient::connect_with_timeout(tasks, url, timeout_ms=5000)
/// ```
pub async fn[X] CdpClient::connect_with_timeout(
  tasks : @async.TaskGroup[X],
  web_socket_url : String,
  timeout_ms? : Int = 25000,
) -> CdpClient {
  let timeout_ms = checked_duration(timeout_ms, "timeout")
  let result : Result[@websocket.Conn?, Error] = try_result_client_client(() => {
    @async.with_timeout_opt(timeout_ms, () => @websocket.connect(web_socket_url))
  })
  match result {
    Ok(Some(ws)) => CdpClient::from_websocket(tasks, ws)
    Ok(None) =>
      raise CdpConnectionError::ConnectionTimeout(web_socket_url, timeout_ms)
    Err(_) =>
      raise CdpConnectionError::WebSocketHandshakeFailed(
        web_socket_url, "websocket connect failed",
      )
  }
}

///|
/// Wraps an already-open WebSocket as a CDP client.
fn[X] CdpClient::from_websocket(
  tasks : @async.TaskGroup[X],
  ws : @websocket.Conn,
) -> CdpClient {
  let client = CdpClient::new(ws)
  tasks.spawn_bg(() => client.read_messages(), no_wait=true, allow_failure=true)
  client
}

///|
fn CdpClient::new(ws : @websocket.Conn) -> CdpClient {
  let client = CdpClient::{
    ws,
    next_id: 1,
    next_event_handler_id: 1,
    next_close_handler_id: 1,
    pending_commands: {},
    command_contexts: {},
    closed: false,
    event_changed: @async.CondVar::Cond(),
    last_command_failure: None,
    cdp_event_handlers: [],
    close_handlers: [],
    last_cdp_request: None,
    last_cdp_response: None,
    last_cdp_event: None,
    attached_targets: {},
  }
  client
}

///|
/// Connects to a parsed CDP target.
///
/// `WebSocket` targets are used directly. `Http` targets are resolved through
/// `/json/version` before opening the browser WebSocket.
///
/// This is a browser-level connection helper. For page-scoped domains such as
/// `Runtime`, `Page`, `DOM`, or `Network`, use `connect_cdp_page_target` unless
/// you explicitly plan to attach through `Target.*` sessions.
///
/// Example:
/// ```
/// // let target = parse_cdp_target("9222")
/// // let client = connect_cdp_target(tasks, target)
/// ```
pub async fn[X] connect_cdp_target(
  tasks : @async.TaskGroup[X],
  target : CdpTarget,
) -> CdpClient {
  let web_socket_url = discover_web_socket_url(target)
  CdpClient::connect(tasks, web_socket_url)
}

///|
/// Connects to a parsed CDP target with a WebSocket timeout.
///
/// Discovery is performed before the WebSocket timeout is applied. Use the
/// lower-level discovery functions directly when you need separate timeout or
/// retry behavior for HTTP discovery.
///
/// Example:
/// ```
/// // let client = connect_cdp_target_with_timeout(tasks, target, timeout_ms=5000)
/// ```
pub async fn[X] connect_cdp_target_with_timeout(
  tasks : @async.TaskGroup[X],
  target : CdpTarget,
  timeout_ms? : Int = 25000,
) -> CdpClient {
  let web_socket_url = discover_web_socket_url(target)
  CdpClient::connect_with_timeout(tasks, web_socket_url, timeout_ms~)
}

///|
/// Connects to the browser-level CDP WebSocket for a parsed target.
///
/// This is the right connection for Browser and Target domain commands such as
/// `Browser.getVersion`, `Target.getTargets`, and `Target.createTarget`.
/// Browser-level connections can also send page commands when paired with a
/// flattened `session_id` returned by `attach_to_target`.
///
/// Example:
/// ```
/// // let client = connect_cdp_browser_target(tasks, parse_cdp_target("9222"))
/// ```
pub async fn[X] connect_cdp_browser_target(
  tasks : @async.TaskGroup[X],
  target : CdpTarget,
) -> CdpClient {
  let web_socket_url = discover_browser_web_socket_url(target)
  CdpClient::connect(tasks, web_socket_url)
}

///|
/// Connects to the browser-level CDP WebSocket with a timeout.
///
/// Example:
/// ```
/// // let client = connect_cdp_browser_target_with_timeout(tasks, target, timeout_ms=5000)
/// ```
pub async fn[X] connect_cdp_browser_target_with_timeout(
  tasks : @async.TaskGroup[X],
  target : CdpTarget,
  timeout_ms? : Int = 25000,
) -> CdpClient {
  let web_socket_url = discover_browser_web_socket_url(target)
  CdpClient::connect_with_timeout(tasks, web_socket_url, timeout_ms~)
}

///|
/// Connects to a page-level CDP WebSocket selected from `/json/list`.
///
/// When a direct page WebSocket is provided and no filters are set, it is used
/// directly. Otherwise this resolves the first page target matching `target_id`,
/// `url`, and `title`.
///
/// All provided filters must match exactly. When no filters are supplied, the
/// first discovered `page` target is selected. The returned client talks
/// directly to that page target, so commands normally do not need `session_id`.
///
/// Example:
/// ```
/// // let client = connect_cdp_page_target(tasks, parse_cdp_target("9222"), title="Example")
/// ```
pub async fn[X] connect_cdp_page_target(
  tasks : @async.TaskGroup[X],
  target : CdpTarget,
  target_id? : String,
  url? : String,
  title? : String,
) -> CdpClient {
  let web_socket_url = discover_page_web_socket_url(
    target,
    target_id?,
    url?,
    title?,
  )
  CdpClient::connect(tasks, web_socket_url)
}

///|
/// Connects to a selected page-level CDP WebSocket with a timeout.
///
/// Example:
/// ```
/// // let client = connect_cdp_page_target_with_timeout(tasks, target, target_id="page-1", timeout_ms=5000)
/// ```
pub async fn[X] connect_cdp_page_target_with_timeout(
  tasks : @async.TaskGroup[X],
  target : CdpTarget,
  target_id? : String,
  url? : String,
  title? : String,
  timeout_ms? : Int = 25000,
) -> CdpClient {
  let web_socket_url = discover_page_web_socket_url(
    target,
    target_id?,
    url?,
    title?,
  )
  CdpClient::connect_with_timeout(tasks, web_socket_url, timeout_ms~)
}

///|
/// Closes the WebSocket and completes all in-flight waits as connection closed.
///
/// The last-message diagnostics remain available after close. Events are live
/// notifications and are not retained for replay.
///
/// Example:
/// ```
/// // defer client.close()
/// ```
pub fn CdpClient::close(self : CdpClient) -> Unit {
  if self.closed {
    return
  }
  self.mark_connection_closed()
  self.ws.close()
}

///|
/// Sends one raw CDP command and waits for the matching response.
///
/// This helper does not validate method names, params, or result shapes against
/// the bundled protocol manifest. Use `send_schema_command` for bundled-schema
/// validation.
///
/// The connection's single reader routes responses directly to their matching
/// waiters and delivers events to registered handlers while this call waits.
///
/// Example:
/// ```
/// // let response = client.send_command("Browser.getVersion")
/// ```
pub async fn CdpClient::send_command(
  self : CdpClient,
  method_name : String,
  params? : Json,
  session_id? : String,
) -> @protocol.CdpResponseMessage {
  let id = self.send_cdp_command(method_name, params?, session_id?)
  self.recv_cdp_response(id)
}

///|
/// Sends one command after validating it against the bundled protocol schema.
///
/// The command params are checked before sending, and the response result is
/// checked before returning. CDP error responses are passed through so callers
/// can inspect the browser error.
///
/// Use this for dynamic JSON params when you want immediate feedback for
/// unknown methods, missing required params, unexpected params, and modeled
/// result-shape mismatches.
///
/// Example:
/// ```
/// // let response = client.send_schema_command("Browser.getVersion")
/// ```
pub async fn CdpClient::send_schema_command(
  self : CdpClient,
  method_name : String,
  params? : Json,
  session_id? : String,
  timeout_ms? : Int = 25000,
) -> @protocol.CdpResponseMessage {
  let command = @protocol.cdp_schema_command(
    id=self.next_id,
    method_name~,
    params?,
    session_id?,
  )
  self.send_cdp_message(command, timeout_ms~)
}

///|
/// Sends one command after validating it against a remote `/json/protocol`.
///
/// This prevents sending a method that exists in the bundled schema but is not
/// advertised by the connected browser. It still uses the bundled typed command
/// builder for local params/result validation.
///
/// Pass the remote schema returned by `discover_protocol`. This helper checks
/// only command presence in the remote schema; detailed local-vs-remote diffs
/// are available through `protocol_schema_diff`.
///
/// Example:
/// ```
/// // let schema = discover_protocol(parse_cdp_target("9222"))
/// // let response = client.send_remote_schema_command(schema, "Browser.getVersion")
/// ```
pub async fn CdpClient::send_remote_schema_command(
  self : CdpClient,
  remote_schema : Json,
  method_name : String,
  params? : Json,
  session_id? : String,
  timeout_ms? : Int = 25000,
) -> @protocol.CdpResponseMessage {
  let command = @protocol.cdp_remote_schema_command(
    id=self.next_id,
    method_name~,
    remote_schema~,
    params?,
    session_id?,
  )
  self.send_cdp_message(command, timeout_ms~)
}

///|
/// Sends a prepared CDP command message and waits for its response.
///
/// Use this when the command was built by a generated domain-specific builder,
/// for example `runtime_evaluate_command`.
///
/// The supplied command id is reserved before sending. It must be positive and
/// not already in flight. The response is validated against the bundled schema
/// for `command.method_name` before it is returned.
///
/// Example:
/// ```
/// // let response = client.send_cdp_message(command, timeout_ms=5000)
/// ```
pub async fn CdpClient::send_cdp_message(
  self : CdpClient,
  command : @protocol.CdpCommandMessage,
  timeout_ms? : Int = 25000,
) -> @protocol.CdpResponseMessage {
  self.send_cdp_message_no_wait(command)
  let response = self.recv_cdp_response(command.id, timeout_ms~)
  @protocol.cdp_schema_response(method_name=command.method_name, response)
}

///|
/// Sends a raw CDP command without waiting and returns the assigned id.
///
/// The caller must later call `recv_cdp_response(id)` to complete the request.
/// This is useful when multiple commands are in flight or when the caller wants
/// to receive events before waiting for a response.
///
/// The command id is allocated from the client's monotonically increasing id
/// counter. The command context is retained until its response is received or
/// the wait times out.
///
/// Example:
/// ```
/// // let id = client.send_cdp_command("Runtime.enable", session_id=session)
/// // let response = client.recv_cdp_response(id)
/// ```
pub async fn CdpClient::send_cdp_command(
  self : CdpClient,
  method_name : String,
  params? : Json,
  session_id? : String,
) -> Int {
  guard !self.closed else { raise BrowserError::ConnectionClosed }
  let id = self.next_id
  self.next_id = self.next_id + 1
  let command = @protocol.cdp_command(id~, method_name~, params?, session_id?)
  self.last_cdp_request = Some(command)
  self.command_contexts[id] = { method_name, session_id }
  self.pending_commands[id] = {
    state: Waiting,
    changed: @async.CondVar::Cond(),
  }
  errdefer self.clear_inflight_command(id)
  self.ws.send_text(command.stringify())
  id
}

///|
/// Waits for the response with the requested command id.
///
/// The connection reader completes the matching pending command directly. A
/// timeout removes only that command; a later response for it is discarded.
///
/// Example:
/// ```
/// // let id = client.send_cdp_command("Browser.getVersion")
/// // let response = client.recv_cdp_response(id, timeout_ms=5000)
/// ```
pub async fn CdpClient::recv_cdp_response(
  self : CdpClient,
  id : Int,
  timeout_ms? : Int = 25000,
) -> @protocol.CdpResponseMessage {
  let timeout_ms = checked_duration(timeout_ms, "timeout")
  defer self.clear_inflight_command(id)
  match @async.with_timeout_opt(timeout_ms, () => self.recv_response(id)) {
    Some(response) => response
    None => raise BrowserError::WaitTimeout("cdp response \{id}")
  }
}

///|
/// Sends a prepared command message without waiting for the response.
async fn CdpClient::send_cdp_message_no_wait(
  self : CdpClient,
  command : @protocol.CdpCommandMessage,
) -> Unit {
  self.reserve_cdp_command_id(command.id)
  self.last_cdp_request = Some(command)
  self.command_contexts[command.id] = {
    method_name: command.method_name,
    session_id: command.session_id,
  }
  self.pending_commands[command.id] = {
    state: Waiting,
    changed: @async.CondVar::Cond(),
  }
  errdefer self.clear_inflight_command(command.id)
  self.ws.send_text(command.stringify())
}

///|
/// Reserves an externally supplied CDP command id.
fn CdpClient::reserve_cdp_command_id(
  self : CdpClient,
  id : Int,
) -> Unit raise BrowserError {
  if self.closed {
    raise ConnectionClosed
  }
  if id <= 0 || self.pending_commands.contains(id) {
    raise InvalidField("id")
  }
  if id >= self.next_id {
    self.next_id = id + 1
  }
}

///|
/// Waits until the connection reader completes the requested command.
async fn CdpClient::recv_response(
  self : CdpClient,
  id : Int,
) -> @protocol.CdpResponseMessage {
  guard self.pending_commands.get(id) is Some(pending) else {
    if self.closed {
      raise BrowserError::ConnectionClosed
    }
    raise BrowserError::InvalidField("id")
  }
  while pending.state is Waiting {
    pending.changed.wait()
  }
  match pending.state {
    Completed(response) => response
    ConnectionClosed => raise BrowserError::ConnectionClosed
    Waiting => abort("CDP command resumed without a completion")
  }
}

///|
/// Returns the last CDP error response context observed by this client.
///
/// This value is updated only when a response contains a CDP `error` object.
/// Successful responses do not clear it, so callers can inspect the last
/// failure after a sequence of commands.
///
/// Example:
/// ```
/// // if client.last_command_failure() is Some(failure) { println(failure.message) }
/// ```
pub fn CdpClient::last_command_failure(self : CdpClient) -> CdpCommandFailure? {
  self.last_command_failure
}

///|
/// Returns the last CDP request sent by this client.
///
/// Example:
/// ```
/// // let last = client.last_cdp_request()
/// ```
pub fn CdpClient::last_cdp_request(
  self : CdpClient,
) -> @protocol.CdpCommandMessage? {
  self.last_cdp_request
}

///|
/// Returns the last CDP response received by this client.
///
/// Example:
/// ```
/// // let last = client.last_cdp_response()
/// ```
pub fn CdpClient::last_cdp_response(
  self : CdpClient,
) -> @protocol.CdpResponseMessage? {
  self.last_cdp_response
}

///|
/// Returns the last CDP event received by this client.
///
/// Example:
/// ```
/// // let last = client.last_cdp_event()
/// ```
pub fn CdpClient::last_cdp_event(
  self : CdpClient,
) -> @protocol.CdpEventMessage? {
  self.last_cdp_event
}

///|
/// Returns all targets currently tracked as attached.
///
/// The cache is updated from Target/Inspector events seen by this client. It is
/// not a browser-wide query; use `get_targets` for the live target list.
/// The returned array is a snapshot of the cache at call time.
///
/// Example:
/// ```
/// // let attached = client.attached_targets()
/// ```
pub fn CdpClient::attached_targets(
  self : CdpClient,
) -> Array[CdpAttachedTarget] {
  let targets : Array[CdpAttachedTarget] = []
  for _, target in self.attached_targets {
    targets.push(target)
  }
  targets
}

///|
/// Returns cached metadata for one attached session.
///
/// Example:
/// ```
/// // let info = client.attached_target(session_id)
/// ```
pub fn CdpClient::attached_target(
  self : CdpClient,
  session_id : String,
) -> CdpAttachedTarget? {
  self.attached_targets.get(session_id)
}

///|
/// Registers an in-process callback for matching CDP events.
///
/// Returns a handler id that can be passed to `remove_cdp_event_handler`.
/// Handlers run synchronously while the client records events.
///
/// Keep handlers small. A handler that blocks or raises will interrupt the
/// read path that is currently waiting for a response or event.
///
/// Example:
/// ```
/// // let id = client.on_cdp_event(method_name="Runtime.consoleAPICalled", fn(event) { ignore(event) })
/// ```
pub fn CdpClient::on_cdp_event(
  self : CdpClient,
  method_name? : String,
  session_id? : String,
  handler : (@protocol.CdpEventMessage) -> Unit,
) -> Int {
  let id = self.next_event_handler_id
  self.next_event_handler_id = id + 1
  self.cdp_event_handlers.push({ id, method_name, session_id, handler })
  id
}

///|
/// Removes a previously registered event handler.
///
/// Returns `true` when a handler was removed.
///
/// Example:
/// ```
/// // ignore(client.remove_cdp_event_handler(id))
/// ```
pub fn CdpClient::remove_cdp_event_handler(self : CdpClient, id : Int) -> Bool {
  let kept : Array[CdpEventHandler] = []
  let mut removed = false
  for handler in self.cdp_event_handlers {
    if handler.id == id {
      removed = true
    } else {
      kept.push(handler)
    }
  }
  self.cdp_event_handlers.clear()
  for handler in kept {
    self.cdp_event_handlers.push(handler)
  }
  removed
}

///|
/// Registers a synchronous notification for connection closure.
pub fn CdpClient::on_close(self : CdpClient, handler : () -> Unit) -> Int {
  let id = self.next_close_handler_id
  self.next_close_handler_id = id + 1
  if self.closed {
    handler()
  } else {
    self.close_handlers.push({ id, handler })
  }
  id
}

///|
/// Removes a previously registered connection-close handler.
pub fn CdpClient::remove_close_handler(self : CdpClient, id : Int) -> Bool {
  let kept : Array[CdpCloseHandler] = []
  let mut removed = false
  for handler in self.close_handlers {
    if handler.id == id {
      removed = true
    } else {
      kept.push(handler)
    }
  }
  self.close_handlers.clear()
  for handler in kept {
    self.close_handlers.push(handler)
  }
  removed
}

///|
/// Waits for the next incoming event matching the filters.
///
/// This observes future events only. Events are never replayed as lifecycle
/// notifications.
///
/// Example:
/// ```
/// // let event = client.recv_cdp_event(method_name="Page.loadEventFired", session_id=session)
/// ```
pub async fn CdpClient::recv_cdp_event(
  self : CdpClient,
  method_name? : String,
  session_id? : String,
) -> @protocol.CdpEventMessage {
  let completion : Ref[@protocol.CdpEventMessage?] = Ref(None)
  let handler_id = self.on_cdp_event(method_name?, session_id?, event => {
    if completion.val is None {
      completion.val = Some(event)
      self.event_changed.broadcast()
    }
  })
  defer ignore(self.remove_cdp_event_handler(handler_id))
  while completion.val is None && !self.closed {
    self.event_changed.wait()
  }
  match completion.val {
    Some(event) => event
    None => raise BrowserError::ConnectionClosed
  }
}

///|
async fn CdpClient::read_messages(self : CdpClient) -> Unit {
  defer self.mark_connection_closed()
  for ;; {
    let message = self.ws.recv()
    let text = message.read_all().text()
    match @protocol.parse_cdp_incoming(@json.parse(text)) {
      Response(response) => self.complete_response(response)
      Event(event) => self.record_cdp_event(event)
    }
  }
}

///|
fn CdpClient::complete_response(
  self : CdpClient,
  response : @protocol.CdpResponseMessage,
) -> Unit {
  self.record_response(response)
  guard self.pending_commands.get(response.id) is Some(pending) else { return }
  if pending.state is Waiting {
    pending.state = Completed(response)
    pending.changed.broadcast()
  }
}

///|
fn CdpClient::mark_connection_closed(self : CdpClient) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  self.event_changed.broadcast()
  for _, pending in self.pending_commands {
    if pending.state is Waiting {
      pending.state = ConnectionClosed
      pending.changed.broadcast()
    }
  }
  for handler in self.close_handlers {
    (handler.handler)()
  }
  self.close_handlers.clear()
}

///|
/// Records one incoming CDP event and invokes matching handlers.
fn CdpClient::record_cdp_event(
  self : CdpClient,
  event : @protocol.CdpEventMessage,
) -> Unit {
  self.last_cdp_event = Some(event)
  match event.method_name {
    "Target.attachedToTarget" => self.record_target_attached(event.params)
    "Target.detachedFromTarget" => self.record_target_detached(event.params)
    "Inspector.detached" => self.record_inspector_detached(event)
    _ => ()
  }
  for handler in self.cdp_event_handlers {
    if cdp_event_matches(
        event,
        method_name?=handler.method_name,
        session_id?=handler.session_id,
      ) {
      (handler.handler)(event)
    }
  }
}

///|
/// Updates the attached-target cache from `Target.attachedToTarget`.
fn CdpClient::record_target_attached(self : CdpClient, params : Json?) -> Unit {
  guard params is Some(Object(fields)) else { return }
  guard fields is { "targetInfo": Object(target), .. } else { return }
  let session_id = optional_json_string(fields, "sessionId").unwrap_or("")
  if session_id == "" {
    return
  }
  self.attached_targets[session_id] = {
    session_id,
    target_id: optional_json_string(target, "targetId").unwrap_or(""),
    target_type: optional_json_string(target, "type").unwrap_or(""),
    title: optional_json_string(target, "title").unwrap_or(""),
    url: optional_json_string(target, "url").unwrap_or(""),
    attached: optional_json_bool(target, "attached").unwrap_or(false),
    browser_context_id: optional_json_string(target, "browserContextId"),
    waiting_for_debugger: optional_json_bool(fields, "waitingForDebugger").unwrap_or(
      false,
    ),
  }
}

///|
/// Updates the attached-target cache from `Target.detachedFromTarget`.
fn CdpClient::record_target_detached(self : CdpClient, params : Json?) -> Unit {
  guard params is Some(Object(fields)) else { return }
  match optional_json_string(fields, "sessionId") {
    Some(session_id) => self.attached_targets.remove(session_id)
    None => ()
  }
}

///|
/// Removes a session from the attached-target cache after `Inspector.detached`.
fn CdpClient::record_inspector_detached(
  self : CdpClient,
  event : @protocol.CdpEventMessage,
) -> Unit {
  match event.session_id {
    Some(session_id) => self.attached_targets.remove(session_id)
    None => ()
  }
}

///|
/// Records response diagnostics when the connection reader receives a response.
fn CdpClient::record_response(
  self : CdpClient,
  response : @protocol.CdpResponseMessage,
) -> Unit {
  self.last_cdp_response = Some(response)
  if response.error is Some(error) {
    let context = self.command_contexts.get(response.id)
    self.last_command_failure = Some({
      id: response.id,
      method_name: match context {
        Some(context) => context.method_name
        None => ""
      },
      session_id: match context {
        Some(context) => context.session_id
        None => response.session_id
      },
      code: error.code,
      message: error.message,
      data: error.data,
    })
  }
  self.command_contexts.remove(response.id)
}

///|
/// Clears state for one completed, failed, timed-out, or cancelled command id.
fn CdpClient::clear_inflight_command(self : CdpClient, id : Int) -> Unit {
  self.command_contexts.remove(id)
  self.pending_commands.remove(id)
}

///|
/// Checks whether an event matches optional method/session filters.
fn cdp_event_matches(
  event : @protocol.CdpEventMessage,
  method_name? : String,
  session_id? : String,
) -> Bool {
  let method_matches = match method_name {
    Some(method_name) => event.method_name == method_name
    None => true
  }
  let session_matches = match session_id {
    Some(session_id) => event.session_id == Some(session_id)
    None => true
  }
  method_matches && session_matches
}

///|
/// Reads an optional string from a JSON object map.
fn optional_json_string(fields : Map[String, Json], name : String) -> String? {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
/// Reads an optional boolean from a JSON object map.
fn optional_json_bool(fields : Map[String, Json], name : String) -> Bool? {
  match fields.get(name) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}
