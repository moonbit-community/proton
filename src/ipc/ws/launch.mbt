///|
let ws_ipc_host = "127.0.0.1"

///|
let ws_ipc_health_path = "/__proton__/health"

///|
let ws_ipc_socket_path = "/__proton__/ws"

///|
let ws_ipc_health_transport = "proton-ipc-ws"

///|
let ws_ipc_health_version = "1"

///|
let ws_ipc_token_counter : Ref[Int64] = Ref(0L)

///|
priv struct WsIpcHealthResponse {
  ok : Bool
  transport : String
  version : String
} derive(FromJson)

///|
/// Launch-time settings shared by the framework and user process.
pub(all) struct WsIpcLaunchConfig {
  host : String
  token : String
  ports : Array[Int]
  health_path : String
  ws_path : String
} derive(ToJson, FromJson, Eq, Debug)

///|
/// Creates a launch config from explicit fields.
///
/// Low-level callers may use this for tests or custom launchers. The transport
/// validates the value again before spawning, probing, or serving IPC.
pub fn WsIpcLaunchConfig::new(
  token : String,
  ports : Array[Int],
  host? : String = ws_ipc_host,
  health_path? : String = ws_ipc_health_path,
  ws_path? : String = ws_ipc_socket_path,
) -> WsIpcLaunchConfig {
  WsIpcLaunchConfig::{
    host,
    token,
    ports: copy_ints(ports),
    health_path,
    ws_path,
  }
}

///|
/// Creates a launch config with a fresh token and deterministic port candidates.
pub fn WsIpcLaunchConfig::auto() -> WsIpcLaunchConfig {
  match WsIpcLaunchConfig::auto_with_token(generate_ws_ipc_token()) {
    Ok(config) => config
    Err(message) => abort(message)
  }
}

///|
/// Creates a launch config with a caller-provided token.
///
/// loopback binding and Origin checks.
pub fn WsIpcLaunchConfig::auto_with_token(
  token : String,
) -> Result[WsIpcLaunchConfig, String] {
  validate_ws_ipc_token(token).map(fn(_) {
    let base = ws_ipc_auto_port_base()
    WsIpcLaunchConfig::new(token, make_port_candidates(base))
  })
}

///|
/// Waits until the WebSocket IPC server is reachable.
///
/// Use this when the current process owns the IPC server and is about to start
/// a framework child process. There is no child process to watch in that mode.
pub async fn wait_ws_ipc_ready(
  config : WsIpcLaunchConfig,
  timeout_ms? : Int = 3000,
  interval_ms? : Int = 50,
) -> Result[Int, String] {
  wait_ws_ipc_ready_async(config, timeout_ms, interval_ms)
}

///|
async fn wait_ws_ipc_ready_async(
  config : WsIpcLaunchConfig,
  timeout_ms : Int,
  interval_ms : Int,
) -> Result[Int, String] {
  match validate_ws_ipc_launch_config(config) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let started_at = @async.now()
  let timeout = timeout_ms.to_int64()
  let interval = if interval_ms <= 0 { 50 } else { interval_ms }
  while @async.now() - started_at <= timeout {
    match find_ready_port_once(config) {
      Some(port) => return Ok(port)
      None => ()
    }
    @async.sleep(interval)
  }
  Err("WebSocket IPC server did not become ready before timeout")
}

///|
async fn find_ready_port_once(config : WsIpcLaunchConfig) -> Int? {
  for port in config.ports {
    let checked = try {
      let (response, body) = @http.get(health_url(config, port))
      response.code == 200 && ws_ipc_health_body_is_valid(body.text())
    } catch {
      _ => false
    }
    if checked {
      return Some(port)
    }
  }
  None
}

///|
fn health_url(config : WsIpcLaunchConfig, port : Int) -> String {
  "http://" +
  config.host +
  ":" +
  port.to_string() +
  config.health_path +
  "?token=" +
  percent_encode_query_value(config.token)
}

///|
fn ws_ipc_health_body() -> String {
  Json::object({
    "ok": Json::boolean(true),
    "transport": Json::string(ws_ipc_health_transport),
    "version": Json::string(ws_ipc_health_version),
  }).stringify()
}

///|
fn ws_ipc_health_body_is_valid(text : String) -> Bool {
  try {
    let json : Json = @json.parse(text)
    let body : WsIpcHealthResponse = @json.from_json(json)
    body.ok &&
    body.transport == ws_ipc_health_transport &&
    body.version == ws_ipc_health_version
  } catch {
    _ => false
  }
}

///|
fn make_port_candidates(base : Int) -> Array[Int] {
  let ports : Array[Int] = []
  for offset in 0..<32 {
    let port = base + offset
    if port > 1024 && port <= 65535 {
      ports.push(port)
    }
  }
  ports
}

///|
fn ws_ipc_auto_port_base() -> Int {
  let now = @async.now()
  41000 + (now % 12000L).to_int()
}

///|
fn validate_ws_ipc_token(token : String) -> Result[Unit, String] {
  guard token.trim().to_owned() != "" else {
    return Err("WebSocket IPC token must not be empty")
  }
  for _, ch in token {
    let code = ch.to_int()
    guard code >= 0x21 && code <= 0x7e else {
      return Err("WebSocket IPC token must be printable ASCII")
    }
  }
  Ok(())
}

///|
fn validate_ws_ipc_launch_config(
  config : WsIpcLaunchConfig,
) -> Result[Unit, String] {
  match validate_ws_ipc_token(config.token) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match validate_ws_ipc_host(config.host) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match validate_ws_ipc_ports(config.ports) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match validate_ws_ipc_path("health", config.health_path) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match validate_ws_ipc_path("websocket", config.ws_path) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  guard config.health_path != config.ws_path else {
    return Err("WebSocket IPC health and websocket paths must be different")
  }
  Ok(())
}

///|
fn validate_ws_ipc_host(host : String) -> Result[Unit, String] {
  let value = host.trim().to_owned()
  guard value == host else { return Err("WebSocket IPC host must be loopback") }
  guard value == "127.0.0.1" || value == "localhost" || value == "[::1]" else {
    return Err("WebSocket IPC host must be loopback")
  }
  Ok(())
}

///|
fn validate_ws_ipc_ports(ports : Array[Int]) -> Result[Unit, String] {
  guard ports.length() > 0 else {
    return Err("WebSocket IPC port candidates must not be empty")
  }
  let seen : Map[Int, Bool] = {}
  for port in ports {
    guard port > 0 && port <= 65535 else {
      return Err(
        "WebSocket IPC port candidate out of range: " + port.to_string(),
      )
    }
    guard seen.get(port) is None else {
      return Err("duplicate WebSocket IPC port candidate: " + port.to_string())
    }
    seen[port] = true
  }
  Ok(())
}

///|
fn validate_ws_ipc_path(kind : String, path : String) -> Result[Unit, String] {
  guard path.has_prefix("/") &&
    path.length() > 1 &&
    !path.has_prefix("//") &&
    path.find("?") is None &&
    path.find("#") is None else {
    return Err("WebSocket IPC " + kind + " path must be an absolute path")
  }
  for _, ch in path {
    guard !ch.is_whitespace() else {
      return Err("WebSocket IPC " + kind + " path must not contain whitespace")
    }
  }
  Ok(())
}

///|
fn generate_ws_ipc_token() -> String {
  let now = @async.now()
  ws_ipc_token_counter.val += 1L
  let seed = Buffer()
  seed.write_string_utf8("proton-ipc-ws-v1")
  seed.write_int64_le(now)
  seed.write_int64_le(ws_ipc_token_counter.val)
  seed.write_int64_le(now + 17L)
  seed.write_int64_le(now + 97L)
  @crypto.bytes_to_hex_string(@crypto.sha256(seed.contents()))
}
