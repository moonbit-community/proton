///|
/// Renders the JavaScript bridge used by WebView pages to reach the user process.
pub fn make_ws_ipc_bridge_script(
  config : WsIpcLaunchConfig,
  op_names : Array[String],
) -> String {
  match validate_ws_ipc_bridge_script_config(config, op_names) {
    Err(error) => abort("make_ws_ipc_bridge_script: " + error)
    Ok(_) => ()
  }
  let ports_json = ToJson::to_json(config.ports).stringify()
  let token_json = Json::string(config.token).stringify()
  let host_json = Json::string(config.host).stringify()
  let health_path_json = Json::string(config.health_path).stringify()
  let ws_path_json = Json::string(config.ws_path).stringify()
  let health_transport_json = Json::string(ws_ipc_health_transport).stringify()
  let health_version_json = Json::string(ws_ipc_health_version).stringify()
  let ipc_protocol_version_json = @ipc.protocol_version().to_string()
  let op_names_json = ToJson::to_json(op_names).stringify()
  let script =
    #|(function() {
    #|  const root = window.__MoonBit__ || (window.__MoonBit__ = Object.create(null));
    #|  const core = root.core || (root.core = Object.create(null));
    #|  const events = root.events || (root.events = Object.create(null));
    #|  const config = {
    #|    host: __HOST__,
    #|    token: __TOKEN__,
    #|    ports: __PORTS__,
    #|    healthPath: __HEALTH_PATH__,
    #|    wsPath: __WS_PATH__,
    #|    healthTransport: __HEALTH_TRANSPORT__,
    #|    healthVersion: __HEALTH_VERSION__
    #|  };
    #|  const ipcProtocolVersion = __IPC_PROTOCOL_VERSION__;
    #|  const opNames = __OP_NAMES__;
    #|  let socket = null;
    #|  let connectPromise = null;
    #|  let nextId = 1;
    #|  const pending = Object.create(null);
    #|  const remoteOpNames = Object.create(null);
    #|  const previousInvokeOp = typeof core.invokeOp === "function"
    #|    ? core.invokeOp.bind(core)
    #|    : null;
    #|  function healthUrl(port) {
    #|    return "http://" + config.host + ":" + port + config.healthPath + "?token=" + encodeURIComponent(config.token);
    #|  }
    #|  function wsUrl(port) {
    #|    return "ws://" + config.host + ":" + port + config.wsPath + "?token=" + encodeURIComponent(config.token);
    #|  }
    #|  async function healthMatches(response) {
    #|    if (!response.ok) {
    #|      return false;
    #|    }
    #|    try {
    #|      const body = await response.json();
    #|      return !!body
    #|        && body.ok === true
    #|        && body.transport === config.healthTransport
    #|        && body.version === config.healthVersion;
    #|    } catch (_) {
    #|      return false;
    #|    }
    #|  }
    #|  async function findPort() {
    #|    for (const port of config.ports) {
    #|      try {
    #|        const response = await fetch(healthUrl(port), { cache: "no-store" });
    #|        if (await healthMatches(response)) {
    #|          return port;
    #|        }
    #|      } catch (_) {}
    #|    }
    #|    throw new Error("MoonBit WebSocket IPC server is not available");
    #|  }
    #|  function rejectAll(error) {
    #|    for (const id of Object.keys(pending)) {
    #|      pending[id].reject(error);
    #|      delete pending[id];
    #|    }
    #|  }
    #|  function frameVersionMatches(frame) {
    #|    return !!frame && frame.version === ipcProtocolVersion;
    #|  }
    #|  function responsePayloadIsValid(response) {
    #|    return !!response
    #|      && response.version === ipcProtocolVersion
    #|      && typeof response.id === "string"
    #|      && typeof response.status === "number";
    #|  }
    #|  function eventPayloadIsValid(event) {
    #|    return !!event
    #|      && event.version === ipcProtocolVersion
    #|      && typeof event.extension_namespace === "string"
    #|      && event.extension_namespace.length > 0
    #|      && typeof event.event_name === "string"
    #|      && event.event_name.length > 0;
    #|  }
    #|  function handleFrame(raw) {
    #|    let frame;
    #|    try {
    #|      frame = JSON.parse(raw);
    #|    } catch (error) {
    #|      return;
    #|    }
    #|    if (!frameVersionMatches(frame)) {
    #|      return;
    #|    }
    #|    if (frame.kind === "response" && responsePayloadIsValid(frame.payload)) {
    #|      const response = frame.payload;
    #|      const callback = pending[response.id];
    #|      if (!callback) {
    #|        return;
    #|      }
    #|      delete pending[response.id];
    #|      if (response.status === 0) {
    #|        callback.resolve(response.body);
    #|      } else {
    #|        callback.reject(response.body);
    #|      }
    #|      return;
    #|    }
    #|    if (frame.kind === "event" && eventPayloadIsValid(frame.payload) && events["@@emitExtensionEvent"]) {
    #|      const event = frame.payload;
    #|      events["@@emitExtensionEvent"](event.extension_namespace, event.event_name, event.payload);
    #|    }
    #|  }
    #|  function connect() {
    #|    if (socket && socket.readyState === WebSocket.OPEN) {
    #|      return Promise.resolve(socket);
    #|    }
    #|    if (connectPromise) {
    #|      return connectPromise;
    #|    }
    #|    connectPromise = findPort().then((port) => new Promise((resolve, reject) => {
    #|      const ws = new WebSocket(wsUrl(port));
    #|      let opened = false;
    #|      ws.onopen = () => {
    #|        opened = true;
    #|        socket = ws;
    #|        resolve(ws);
    #|      };
    #|      ws.onmessage = (event) => handleFrame(String(event.data));
    #|      ws.onerror = () => {
    #|        connectPromise = null;
    #|        reject(new Error("MoonBit WebSocket IPC connection failed"));
    #|      };
    #|      ws.onclose = () => {
    #|        if (socket === ws) {
    #|          socket = null;
    #|        }
    #|        connectPromise = null;
    #|        if (!opened) {
    #|          reject(new Error("MoonBit WebSocket IPC connection closed before opening"));
    #|        }
    #|        rejectAll(new Error("MoonBit WebSocket IPC connection closed"));
    #|      };
    #|    }));
    #|    return connectPromise;
    #|  }
    #|  for (const name of opNames) {
    #|    remoteOpNames[name] = true;
    #|    if (typeof core.registerOp === "function") {
    #|      core.registerOp(name);
    #|    }
    #|  }
    #|  function invokeRemoteOp(name, payload) {
    #|    return connect().then((ws) => new Promise((resolve, reject) => {
    #|      const id = "js-" + nextId++;
    #|      pending[id] = { resolve, reject };
    #|      try {
    #|        ws.send(JSON.stringify({
    #|          version: ipcProtocolVersion,
    #|          kind: "request",
    #|          payload: {
    #|            version: ipcProtocolVersion,
    #|            id,
    #|            name,
    #|            payload: payload === undefined ? null : payload
    #|          }
    #|        }));
    #|      } catch (error) {
    #|        delete pending[id];
    #|        reject(error);
    #|      }
    #|    }));
    #|  }
    #|  core.invokeOp = function(name, payload) {
    #|    if (remoteOpNames[name]) {
    #|      return invokeRemoteOp(name, payload);
    #|    }
    #|    if (previousInvokeOp) {
    #|      return previousInvokeOp(name, payload);
    #|    }
    #|    return Promise.reject(new Error("MoonBit op is not available: " + name));
    #|  };
    #|})()
    #|
  script
  .replace(old="__HOST__", new=host_json)
  .replace(old="__TOKEN__", new=token_json)
  .replace(old="__PORTS__", new=ports_json)
  .replace(old="__HEALTH_PATH__", new=health_path_json)
  .replace(old="__WS_PATH__", new=ws_path_json)
  .replace(old="__HEALTH_TRANSPORT__", new=health_transport_json)
  .replace(old="__HEALTH_VERSION__", new=health_version_json)
  .replace(old="__IPC_PROTOCOL_VERSION__", new=ipc_protocol_version_json)
  .replace(old="__OP_NAMES__", new=op_names_json)
}

///|
fn validate_ws_ipc_bridge_script_config(
  config : WsIpcLaunchConfig,
  op_names : Array[String],
) -> Result[Unit, String] {
  match validate_ws_ipc_launch_config(config) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let seen : Map[String, Bool] = {}
  for op_name in op_names {
    guard op_name.trim().to_owned() != "" else {
      return Err("WebSocket IPC bridge op name must not be empty")
    }
    guard seen.get(op_name) is None else {
      return Err("duplicate WebSocket IPC bridge op name: " + op_name)
    }
    seen[op_name] = true
  }
  Ok(())
}
