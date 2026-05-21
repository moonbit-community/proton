///|
/// Command host intended to run in the MBT process.
///
/// The host is independent from `@webview.Webview`, so application code can use
/// normal MoonBit syntax, state, and `async` handlers without living in the GUI
/// process.
struct MbtProcessHost {
  registry : OpRegistry
  executor : AsyncExecutor
  op_names : Array[String]
  mut closed : Bool
}

///|
/// Creates an empty MBT-side command host.
pub fn MbtProcessHost::new(worker_count? : Int = 4) -> MbtProcessHost {
  MbtProcessHost::{
    registry: OpRegistry::new(),
    executor: AsyncExecutor::new(worker_count~),
    op_names: [],
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
    self.registry.call_async(self.executor, request.name, request.payload, fn(
      reply,
    ) {
      complete(make_ipc_response(request.id, reply))
    })
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
/// Closes the async executor owned by this host.
pub fn MbtProcessHost::close(self : MbtProcessHost) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  self.executor.close()
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
