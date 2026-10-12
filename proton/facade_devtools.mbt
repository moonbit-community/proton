///|
/// A protocol failure or a closed/overloaded native DevTools session.
pub suberror DevToolsError {
  Protocol(code~ : Int, message~ : String, data~ : Json?)
  Closed(String)
  InvalidMessage(String)
} derive(Debug)

///|
/// A CDP event from this page. Domain subscriptions are enabled with commands
/// such as `Runtime.enable` or `Overlay.enable`.
pub struct DevToolsEvent {
  method_ : String
  params : Json
} derive(Debug)

///|
/// A scoped native DevTools connection. Obtain it with
/// `WebContentsHandle::with_devtools`; retaining it does not extend its lifetime.
struct DevToolsSession {
  window : Int64
  view : Int64?
  send : (String) -> Unit raise WindowSessionError
  detach : () -> Unit
  mut closed : String?
  serial : Ref[Int]
  pending : Map[Int, DevToolsPending]
  events : Array[(DevToolsEvent, Int)]
  mut event_bytes : Int
  changed : @async.CondVar
  mut receiving : Bool
}

///|
priv struct DevToolsPending {
  mut result : Result[Json, DevToolsError]?
  changed : @async.CondVar
}

///|
priv struct DevToolsSessions {
  mut serial : Int64
  requests : Ref[Int]
  sessions : Map[Int64, DevToolsSession]
}

///|
fn DevToolsSessions::DevToolsSessions() -> DevToolsSessions {
  { serial: 0L, requests: Ref(0), sessions: {}, }
}

///|
fn DevToolsSession::finish(self : DevToolsSession, reason : String) -> Unit {
  guard self.closed is None else { return }
  self.closed = Some(reason)
  (self.detach)()
  self.events.clear()
  self.event_bytes = 0
  for pending in self.pending.values() {
    pending.result = Some(Err(Closed(reason)))
    pending.changed.broadcast()
  }
  self.changed.broadcast()
}

///|
fn DevToolsSessions::close(self : DevToolsSessions) -> Unit {
  for session in self.sessions.values() {
    session.finish("application has ended")
  }
}

///|
fn DevToolsSessions::route(
  self : DevToolsSessions,
  event : @native.RuntimeEvent,
) -> Bool {
  if event.devtools_message() is Some((token, failed, message)) {
    if self.sessions.get(token) is Some(session) {
      if failed {
        session.finish(message)
      } else {
        session.receive(message) catch {
          error => session.finish(error.to_string())
        }
      }
    }
    return true
  }
  for session in self.sessions.values() {
    if event.window_id() != Some(session.window) {
      continue
    }
    if event.is_window_closed() ||
      (event.is_view_closed() && event.view_id() == session.view) {
      session.finish("page has closed")
    } else if event.renderer_process_termination() is Some(_) &&
      event.view_id() == session.view {
      session.finish("renderer process has terminated")
    }
  }
  false
}

///|
fn DevToolsSession::receive(
  self : DevToolsSession,
  message : String,
) -> Unit raise {
  guard self.closed is None else { return }
  guard @json.parse(message) is Object(fields) else {
    raise InvalidMessage("DevTools message must be an object")
  }
  if fields.get("id") is Some(id) {
    let id : Int = @json.from_json(id)
    // Cancellation unregisters the waiter; discard its late reply.
    if self.pending.get(id) is Some(pending) {
      let result = if fields.get("error") is Some(Object(error)) {
        guard error.get("code") is Some(code) &&
          error.get("message") is Some(String(message)) else {
          raise InvalidMessage("Invalid DevTools error")
        }
        Err(
          Protocol(code=@json.from_json(code), message~, data=error.get("data")),
        )
      } else if fields.get("result") is Some(result) {
        Ok(result)
      } else {
        raise InvalidMessage("DevTools reply has no result or error")
      }
      pending.result = Some(result)
      pending.changed.broadcast()
    }
  } else {
    guard fields.get("method") is Some(String(method_)) else {
      raise InvalidMessage("DevTools event has no method")
    }
    // UTF-16 storage is at most twice the UTF-8 wire size. Bound retained
    // strings as well as native queued messages; overflow terminates the session.
    let size = message.length() * 2
    guard self.events.length() < 256 &&
      self.event_bytes + size <= 16 * 1024 * 1024 else {
      raise InvalidMessage("DevTools event queue limit exceeded")
    }
    self.events.push(
      ({ method_, params: fields.get("params").unwrap_or({}), }, size),
    )
    self.event_bytes += size
    self.changed.broadcast()
  }
}

///|
/// Sends a CDP method to this page and returns its result object. Concurrent
/// commands are matched by request ID. Cancellation removes this waiter; it
/// cannot undo a command already submitted to Chromium. Use `with_timeout` for
/// commands that may wait indefinitely (for example, awaiting a page promise).
pub async fn DevToolsSession::send_command(
  self : DevToolsSession,
  method_ : String,
  params? : Json = {},
) -> Json {
  if self.closed is Some(reason) {
    raise DevToolsError::Closed(reason)
  }
  guard params is Object(_) && !method_.is_empty() else {
    raise InvalidMessage(
      "DevTools requires a non-empty method and object parameters",
    )
  }
  guard self.pending.length() < 256 else {
    raise InvalidMessage("Too many pending DevTools commands")
  }
  guard self.serial.val < 2147483647 else {
    raise InvalidMessage("DevTools request IDs exhausted")
  }
  self.serial.val += 1
  let id = self.serial.val
  let message : Json = {
    "id": id.to_json(),
    "method": method_.to_json(),
    "params": params,
  }
  let message = message.stringify()
  guard @utf8.encode(message).length() <= 2 * 1024 * 1024 else {
    raise InvalidMessage("DevTools command exceeds 2 MiB")
  }
  let pending : DevToolsPending = {
    result: None,
    changed: @async.CondVar::Cond(),
  }
  self.pending.set(id, pending)
  defer self.pending.remove(id)
  (self.send)(message)
  for ;; {
    if pending.result is Some(Ok(result)) {
      return result
    }
    if pending.result is Some(Err(error)) {
      raise error
    }
    pending.changed.wait()
  }
}

///|
/// Reads the next buffered CDP event. Only one event reader may wait at a time;
/// commands can run concurrently. Canceling the reader leaves the session open.
pub async fn DevToolsSession::next_event(
  self : DevToolsSession,
) -> DevToolsEvent {
  guard !self.receiving else {
    raise InvalidMessage("DevTools already has an event reader")
  }
  self.receiving = true
  defer {
    self.receiving = false
  }
  for ;; {
    if self.closed is Some(reason) {
      raise DevToolsError::Closed(reason)
    }
    if !self.events.is_empty() {
      let (event, size) = self.events.remove(0)
      self.event_bytes -= size
      return event
    }
    self.changed.wait()
  }
}

///|
fn WebContentsHandle::devtools_operation(
  self : WebContentsHandle,
  operation : Int,
  token : Int64,
  message : String,
) -> Unit raise WindowSessionError {
  self.with_target("use native DevTools in", target => {
    match target {
      PrimaryPage(window) =>
        window.devtools_operation(operation, token, message)
      ChildView(view) => view.devtools_operation(operation, token, message)
    }
  })
}

///|
/// Opens a native CDP session for exactly this page, without a debugging port or
/// DevTools window. One scoped session per page is allowed. The observer is
/// unregistered on return, error, or cancellation; page closure/renderer termination
/// fails pending operations. Received events are bounded (256 events / 16 MiB),
/// and individual messages are limited to 2 MiB; overflow closes the session.
/// Unregistering does not reset CDP domains or undo commands: disable inspection,
/// release remote objects, and remove bindings explicitly when finished.
/// This is a trusted backend API and must not be exposed to untrusted page code.
pub async fn[T] WebContentsHandle::with_devtools(
  self : WebContentsHandle,
  callback : async (DevToolsSession) -> T,
) -> T {
  let store = self.session.event_pump.devtools
  guard store.serial < 9223372036854775807L else {
    raise InvalidMessage("DevTools session IDs exhausted")
  }
  store.serial += 1
  let token = store.serial
  let session : DevToolsSession = {
    window: self.native_id,
    view: match self.target {
      PrimaryPage => None
      ChildView(_, id) => Some(id)
    },
    send: message => self.devtools_operation(1, token, message),
    // Native page destruction also releases the observer when a retained
    // handle can no longer resolve a live page.
    detach: () => self.devtools_operation(2, token, "") catch { _ => () },
    closed: None,
    serial: store.requests,
    pending: {},
    events: [],
    event_bytes: 0,
    changed: @async.CondVar::Cond(),
    receiving: false,
  }
  self.devtools_operation(0, token, "")
  store.sessions.set(token, session)
  defer {
    session.finish("DevTools scope has ended")
    store.sessions.remove(token)
  }
  callback(session)
}

///|
pub extend DevToolsError with Debug::{to_repr}

///|
pub extend DevToolsEvent with Debug::{to_repr}
