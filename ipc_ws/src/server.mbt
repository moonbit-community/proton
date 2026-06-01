///|
/// Runs a local HTTP/WebSocket IPC server and dispatches request frames.
pub async fn run_ws_ipc_server(
  config : WsIpcLaunchConfig,
  dispatch : async (@ipc.IpcOpRequest) -> @ipc.IpcOpResponse,
) -> Result[Unit, String] {
  run_ws_ipc_server_with_event_sink(config, dispatch)
}

///|
/// Runs a local HTTP/WebSocket IPC server with a process-level event sink.
///
/// `event_sink` is called once after config validation and server binding both
/// succeed. The callback can install the provided async sender into the command
/// host, so extension events are broadcast to all currently connected WebView
/// sockets.
pub async fn run_ws_ipc_server_with_event_sink(
  config : WsIpcLaunchConfig,
  dispatch : async (@ipc.IpcOpRequest) -> @ipc.IpcOpResponse,
  event_sink? : (async (@ipc.IpcExtensionEvent) -> Unit) -> Unit = fn(_emit) {
    ()
  },
) -> Result[Unit, String] {
  match validate_ws_ipc_launch_config(config) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let event_hub = WsIpcEventHub::new()
  let server = match bind_first_available_server(config) {
    Err(message) => return Err(message)
    Ok(server) => server
  }
  event_sink(async fn(event) { event_hub.emit(event) })
  run_ws_ipc_server_core(config, dispatch, event_hub, server)
}

///|
priv struct WsIpcEventHub {
  clients : Map[Int, async (String) -> Unit]
  mut next_id : Int
}

///|
fn WsIpcEventHub::new() -> WsIpcEventHub {
  WsIpcEventHub::{ clients: {}, next_id: 0 }
}

///|
fn WsIpcEventHub::add_client(
  self : WsIpcEventHub,
  send : async (String) -> Unit,
) -> Int {
  let id = self.next_id
  self.next_id = self.next_id + 1
  self.clients[id] = send
  id
}

///|
fn WsIpcEventHub::remove_client(self : WsIpcEventHub, id : Int) -> Unit {
  ignore(self.clients.remove(id))
}

///|
async fn WsIpcEventHub::emit(
  self : WsIpcEventHub,
  event : @ipc.IpcExtensionEvent,
) -> Unit {
  let frame = @ipc.IpcFrame::event(event)
  let event = match frame.as_event() {
    Ok(event) => event
    Err(_) => return
  }
  let frame = @ipc.IpcFrame::event(event).stringify()
  let sends : Array[async (String) -> Unit] = []
  for _, send in self.clients {
    sends.push(send)
  }
  for send in sends {
    send(frame)
  }
}

///|
async fn run_ws_ipc_server_core(
  config : WsIpcLaunchConfig,
  dispatch : async (@ipc.IpcOpRequest) -> @ipc.IpcOpResponse,
  event_hub : WsIpcEventHub,
  server : @http.Server,
) -> Result[Unit, String] {
  match validate_ws_ipc_launch_config(config) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  server.run_forever(
    async fn(request, _body, conn) {
      handle_http_request(config, request, conn, dispatch, event_hub)
    },
    allow_failure=true,
  ) catch {
    err => return Err(err.to_string())
  }
  Ok(())
}

///|
async fn bind_first_available_server(
  config : WsIpcLaunchConfig,
) -> Result[@http.Server, String] {
  for port in config.ports {
    let addr = @socket.Addr::parse(config.host + ":" + port.to_string()) catch {
      err => return Err(err.to_string())
    }
    let server = try @http.Server(addr) catch {
      _ => continue
    } noraise {
      server => server
    }
    return Ok(server)
  }
  Err("failed to bind any WebSocket IPC candidate port")
}

///|
async fn handle_http_request(
  config : WsIpcLaunchConfig,
  request : @http.Request,
  conn : @http.ServerConnection,
  dispatch : async (@ipc.IpcOpRequest) -> @ipc.IpcOpResponse,
  event_hub : WsIpcEventHub,
) -> Unit {
  let origin = request_origin(request)
  if !origin_is_allowed(origin) {
    send_text_response(conn, 403, "Forbidden", "invalid IPC origin")
    return
  }
  if !path_has_token(request.path, config.token) {
    send_text_response(conn, 403, "Forbidden", "invalid IPC token", origin~)
    return
  }
  if path_without_query(request.path) == config.health_path {
    send_text_response(
      conn,
      200,
      "OK",
      ws_ipc_health_body(),
      content_type="application/json",
      origin~,
    )
    return
  }
  if path_without_query(request.path) == config.ws_path {
    serve_websocket(request, conn, dispatch, event_hub)
    return
  }
  send_text_response(conn, 404, "Not Found", "not found", origin~)
}

///|
async fn serve_websocket(
  request : @http.Request,
  conn : @http.ServerConnection,
  dispatch : async (@ipc.IpcOpRequest) -> @ipc.IpcOpResponse,
  event_hub : WsIpcEventHub,
) -> Unit {
  let ws = @websocket.from_http_server(request, conn) catch { _ => return }
  let send_lock = @semaphore.Semaphore(1)
  let client_id = event_hub.add_client(async fn(frame) {
    send_ws_text(ws, send_lock, frame)
  })
  defer event_hub.remove_client(client_id)
  defer ws.close()
  @async.with_task_group(group => {
    for ;; {
      let message = ws.recv() catch {
        @websocket.ConnectionClosed(_) => break
        _ => break
      }
      let raw = message.read_all().text() catch {
          err => {
            send_ws_response(
              ws,
              send_lock,
              "invalid",
              @ipc.IpcOpResponse::err("invalid", err.to_string()),
            )
            continue
          }
        }
      match @ipc.parse_ipc_frame(raw).bind(fn(frame) { frame.as_request() }) {
        Ok(request) =>
          group.spawn_bg(no_wait=true, allow_failure=true, () => {
            let response = dispatch(request) catch {
              err => @ipc.IpcOpResponse::err(request.id, err.to_string())
            }
            send_ws_response(ws, send_lock, request.id, response)
          })
        Err(message) =>
          send_ws_response(
            ws,
            send_lock,
            "invalid",
            @ipc.IpcOpResponse::err("invalid", message),
          )
      }
    }
  })
}

///|
async fn send_ws_response(
  ws : @websocket.Conn,
  send_lock : @semaphore.Semaphore,
  fallback_id : String,
  response : @ipc.IpcOpResponse,
) -> Unit {
  let response = match @ipc.IpcFrame::response(response).as_response() {
    Ok(response) => response
    Err(error) =>
      @ipc.IpcOpResponse::err(fallback_id, "invalid IPC response: " + error)
  }
  send_ws_text(ws, send_lock, @ipc.IpcFrame::response(response).stringify())
}

///|
async fn send_ws_text(
  ws : @websocket.Conn,
  send_lock : @semaphore.Semaphore,
  text : String,
) -> Unit {
  send_lock.acquire()
  defer send_lock.release()
  ws.send_text(text) catch {
    _ => ()
  }
}

///|
async fn send_text_response(
  conn : @http.ServerConnection,
  code : Int,
  reason : String,
  body : String,
  content_type? : String = "text/plain",
  origin? : String? = None,
) -> Unit {
  let headers = { "Content-Type": content_type, "Cache-Control": "no-store" }
  match origin {
    Some(origin) => {
      headers["Access-Control-Allow-Origin"] = origin
      headers["Vary"] = "Origin"
    }
    None => ()
  }
  conn.send_response(code, reason, extra_headers=headers)
  conn.write(body)
  conn.end_response()
}

///|
fn request_origin(request : @http.Request) -> String? {
  header_value(request.headers, "origin")
}

///|
fn header_value(headers : Map[String, String], name : String) -> String? {
  let expected = name.to_lower()
  for key, value in headers {
    if key.to_lower() == expected {
      return Some(value)
    }
  }
  None
}

///|
fn origin_is_allowed(origin : String?) -> Bool {
  match origin {
    None => true
    Some(origin) =>
      origin == "null" ||
      origin.has_prefix("file://") ||
      local_http_origin_is_allowed(origin)
  }
}

///|
fn local_http_origin_is_allowed(origin : String) -> Bool {
  let rest = match strip_origin_scheme(origin) {
    Some(rest) => rest
    None => return false
  }
  let host = origin_host(rest)
  host == "localhost" ||
  host.has_suffix(".localhost") ||
  host == "127.0.0.1" ||
  host == "[::1]"
}

///|
fn strip_origin_scheme(origin : String) -> String? {
  match origin.strip_prefix("http://") {
    Some(rest) => Some(rest.to_owned())
    None =>
      match origin.strip_prefix("https://") {
        Some(rest) => Some(rest.to_owned())
        None => None
      }
  }
}

///|
fn origin_host(rest : String) -> String {
  if rest.has_prefix("[") {
    match rest.find("]") {
      Some(index) => rest[:index + 1].to_owned()
      None => rest
    }
  } else {
    match rest.find(":") {
      Some(index) => rest[:index].to_owned()
      None => rest
    }
  }
}

///|
fn path_without_query(path : String) -> String {
  match path.find("?") {
    Some(index) => path[:index].to_owned()
    None => path
  }
}

///|
fn path_has_token(path : String, token : String) -> Bool {
  match query_param(path, "token") {
    Some(value) => value == token
    None => false
  }
}

///|
fn query_param(path : String, name : String) -> String? {
  let query_start = match path.find("?") {
    Some(index) => index + 1
    None => return None
  }
  let query = path[query_start:].to_owned()
  let mut matched : String? = None
  for part in split_query(query) {
    match part.find("=") {
      Some(index) => {
        let key = part[:index].to_owned()
        if key == name {
          guard matched is None else { return None }
          matched = percent_decode_query_value(part[index + 1:].to_owned())
        }
      }
      None =>
        if part == name {
          guard matched is None else { return None }
          matched = Some("")
        }
    }
  }
  matched
}

///|
fn split_query(query : String) -> Array[String] {
  let parts : Array[String] = []
  let mut start = 0
  for index, ch in query {
    if ch == '&' {
      parts.push(query[start:index].to_owned())
      start = index + 1
    }
  }
  parts.push(query[start:].to_owned())
  parts
}
