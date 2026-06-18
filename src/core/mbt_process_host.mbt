///|
/// Command host intended to run in the MBT process.
///
/// The host is independent from `@webview.Webview`, so application code can use
/// normal MoonBit syntax, state, and `async` handlers without living in the GUI
/// process.
struct MbtProcessHost {
  registry : OpRegistry
  op_names : Array[String]
  mut registration_sealed : Bool
  mut closed : Bool
}

///|
/// Creates an empty MBT-side command host.
pub fn MbtProcessHost::new() -> MbtProcessHost {
  MbtProcessHost::{
    registry: OpRegistry::new(),
    op_names: [],
    registration_sealed: false,
    closed: false,
  }
}

///|
/// Registers a synchronous MBT-side op.
pub fn[Payload : @json.FromJson, Reply : ToJson] MbtProcessHost::op(
  self : MbtProcessHost,
  name : String,
  callback : (Payload) -> Reply,
) -> Unit {
  self.ensure_open_for_register()
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
  self.ensure_open_for_register()
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
  self.ensure_open_for_register()
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
  self.ensure_open_for_register()
  self.registry.handle_async_result(name, callback)
  self.op_names.push(name)
}

///|
/// Returns registered op names in registration order.
pub fn MbtProcessHost::registered_ops(self : MbtProcessHost) -> Array[String] {
  copy_strings(self.op_names)
}

///|
/// Dispatches one decoded IPC request.
///
/// Async handlers complete later through `complete`; synchronous handlers call it
/// before this function returns.
pub fn MbtProcessHost::dispatch(
  self : MbtProcessHost,
  request : @ipc.IpcOpRequest,
  complete : (@ipc.IpcOpResponse) -> Unit,
) -> Unit {
  let fallback_id = ipc_request_fallback_response_id(request)
  let request = match request.validate() {
    Ok(request) => request
    Err(message) => {
      complete(@ipc.IpcOpResponse::err(fallback_id, message))
      return
    }
  }
  guard !self.closed else {
    complete(@ipc.IpcOpResponse::err(request.id, "MBT process host is closed"))
    return
  }
  if self.registry.has_async(request.name) {
    complete(
      @ipc.IpcOpResponse::err(
        request.id,
        "Async MBT process ops require dispatch_async()",
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
/// User command hosts use this path so async ops run inside the user process
/// event loop instead of creating a nested event loop elsewhere.
pub async fn MbtProcessHost::dispatch_async(
  self : MbtProcessHost,
  request : @ipc.IpcOpRequest,
) -> @ipc.IpcOpResponse {
  let fallback_id = ipc_request_fallback_response_id(request)
  let request = match request.validate() {
    Ok(request) => request
    Err(message) => return @ipc.IpcOpResponse::err(fallback_id, message)
  }
  guard !self.closed else {
    return @ipc.IpcOpResponse::err(request.id, "MBT process host is closed")
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
  complete : (@ipc.IpcOpResponse) -> Unit,
) -> Unit {
  match @ipc.parse_ipc_op_request(raw) {
    Ok(request) => self.dispatch(request, complete)
    Err(message) => complete(@ipc.IpcOpResponse::err("invalid", message))
  }
}

///|
/// Parses and dispatches one JSON IPC request payload on the current async loop.
pub async fn MbtProcessHost::dispatch_json_async(
  self : MbtProcessHost,
  raw : String,
) -> @ipc.IpcOpResponse {
  match @ipc.parse_ipc_op_request(raw) {
    Ok(request) => self.dispatch_async(request)
    Err(message) => @ipc.IpcOpResponse::err("invalid", message)
  }
}

///|
/// Prevents later registrations while keeping existing ops dispatchable.
fn MbtProcessHost::seal_registrations(self : MbtProcessHost) -> Unit {
  guard !self.closed else { return }
  self.registration_sealed = true
}

///|
/// Closes this host and rejects future dispatches.
pub fn MbtProcessHost::close(self : MbtProcessHost) -> Unit {
  guard !self.closed else { return }
  self.closed = true
}

///|
fn MbtProcessHost::ensure_open_for_register(self : MbtProcessHost) -> Unit {
  guard !self.closed else {
    abort("MbtProcessHost: cannot register op after close")
  }
  guard !self.registration_sealed else {
    abort("MbtProcessHost: cannot register op after registration is sealed")
  }
}

///|
fn make_ipc_response(
  id : String,
  reply : Result[Json, String],
) -> @ipc.IpcOpResponse {
  match reply {
    Ok(body) => @ipc.IpcOpResponse::ok(id, body)
    Err(message) => @ipc.IpcOpResponse::err(id, message)
  }
}

///|
fn ipc_request_fallback_response_id(request : @ipc.IpcOpRequest) -> String {
  if request.id.trim().to_owned() == "" {
    "invalid"
  } else {
    request.id
  }
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  values.map(fn(value) { value })
}
