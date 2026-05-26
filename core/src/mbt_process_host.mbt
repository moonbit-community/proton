///|
/// Command host intended to run in the MBT process.
///
/// The host is independent from `@webview.Webview`, so application code can use
/// normal MoonBit syntax, state, and `async` handlers without living in the GUI
/// process.
struct MbtProcessHost {
  registry : OpRegistry
  op_names : Array[String]
  mut closed : Bool
}

///|
/// Creates an empty MBT-side command host.
pub fn MbtProcessHost::new(worker_count? : Int = 4) -> MbtProcessHost {
  ignore(worker_count)
  MbtProcessHost::{ registry: OpRegistry::new(), op_names: [], closed: false }
}

///|
/// Registers a synchronous MBT-side op.
pub fn[Payload : @json.FromJson, Reply : ToJson] MbtProcessHost::op(
  self : MbtProcessHost,
  name : String,
  callback : (Payload) -> Reply,
) -> Unit {
  self.registry.handle(name, callback)
  self.op_names.push(name)
}

///|
/// Registers a synchronous MBT-side op that can return a string error.
pub fn[Payload : @json.FromJson, Reply : ToJson] MbtProcessHost::op_result(
  self : MbtProcessHost,
  name : String,
  callback : (Payload) -> Result[Reply, String],
) -> Unit {
  self.registry.handle_result(name, callback)
  self.op_names.push(name)
}

///|
/// Registers an async MBT-side op.
pub fn[Payload : @json.FromJson, Reply : ToJson] MbtProcessHost::op_async(
  self : MbtProcessHost,
  name : String,
  callback : async (Payload) -> Reply,
) -> Unit {
  self.registry.handle_async(name, callback)
  self.op_names.push(name)
}

///|
/// Registers an async MBT-side op that can return a string error.
pub fn[Payload : @json.FromJson, Reply : ToJson] MbtProcessHost::op_async_result(
  self : MbtProcessHost,
  name : String,
  callback : async (Payload) -> Result[Reply, String],
) -> Unit {
  self.registry.handle_async_result(name, callback)
  self.op_names.push(name)
}

///|
/// Returns registered op names in registration order.
pub fn MbtProcessHost::registered_ops(self : MbtProcessHost) -> Array[String] {
  self.op_names
}

///|
/// Dispatches one decoded IPC request.
///
/// Async handlers complete later through `complete`; synchronous handlers call it
/// before this function returns.
pub fn MbtProcessHost::dispatch(
  self : MbtProcessHost,
  request : IpcOpRequest,
  complete : (IpcOpResponse) -> Unit,
) -> Unit {
  guard !self.closed else {
    complete(IpcOpResponse::err(request.id, "MBT process host is closed"))
    return
  }
  if self.registry.has_async(request.name) {
    complete(
      IpcOpResponse::err(
        request.id,
        "Async MBT process ops require dispatch_async() or run_stdio()",
      ),
    )
  } else {
    complete(
      make_ipc_response(
        request.id,
        self.registry.call(request.name, request.payload),
      ),
    )
  }
}

///|
/// Dispatches one decoded IPC request on the current async loop.
///
/// MBT process stdio hosts use this path so async ops run inside the backend
/// process event loop instead of creating a nested event loop elsewhere.
pub async fn MbtProcessHost::dispatch_async(
  self : MbtProcessHost,
  request : IpcOpRequest,
) -> IpcOpResponse {
  guard !self.closed else {
    return IpcOpResponse::err(request.id, "MBT process host is closed")
  }
  if self.registry.has_async(request.name) {
    make_ipc_response(
      request.id,
      self.registry.call_async_direct(request.name, request.payload),
    )
  } else {
    make_ipc_response(
      request.id,
      self.registry.call(request.name, request.payload),
    )
  }
}

///|
/// Parses and dispatches one JSON IPC request payload.
pub fn MbtProcessHost::dispatch_json(
  self : MbtProcessHost,
  raw : String,
  complete : (IpcOpResponse) -> Unit,
) -> Unit {
  match parse_ipc_op_request(raw) {
    Ok(request) => self.dispatch(request, complete)
    Err(message) => complete(IpcOpResponse::err("invalid", message))
  }
}

///|
/// Parses and dispatches one JSON IPC request payload on the current async loop.
pub async fn MbtProcessHost::dispatch_json_async(
  self : MbtProcessHost,
  raw : String,
) -> IpcOpResponse {
  match parse_ipc_op_request(raw) {
    Ok(request) => self.dispatch_async(request)
    Err(message) => IpcOpResponse::err("invalid", message)
  }
}

///|
/// Closes this host and rejects future dispatches.
pub fn MbtProcessHost::close(self : MbtProcessHost) -> Unit {
  guard !self.closed else { return }
  self.closed = true
}

///|
fn make_ipc_response(
  id : String,
  reply : Result[Json, String],
) -> IpcOpResponse {
  match reply {
    Ok(body) => IpcOpResponse::ok(id, body)
    Err(message) => IpcOpResponse::err(id, message)
  }
}
