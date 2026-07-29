///|
priv struct CommandErrorPolicy {
  expose_details : Bool
}

///|
fn CommandErrorPolicy::new(expose_details : Bool) -> CommandErrorPolicy {
  CommandErrorPolicy::{ expose_details, }
}

///|
fn CommandErrorPolicy::response_message(
  self : CommandErrorPolicy,
  error : Error,
  safe_message : String,
) -> String {
  let diagnostic = @debug.render(@debug.to_repr(error))
  if self.expose_details {
    diagnostic
  } else {
    println("[proton] command dispatch failed: " + diagnostic)
    safe_message
  }
}

///|
/// Command host intended to run in the MBT process.
///
/// The host is independent from the browser window, so application code can use
/// normal MoonBit syntax, state, and `async` handlers without living in the GUI
/// process.
struct MbtProcessHost {
  registry : OpRegistry
  op_names : Array[String]
  error_policy : CommandErrorPolicy
  mut registration_sealed : Bool
  mut closed : Bool
}

///|
/// Creates an empty MBT-side command host.
///
/// Handler diagnostics remain in backend logs by default. Set
/// `expose_error_details` only for a trusted development frontend.
pub fn MbtProcessHost::new(
  expose_error_details? : Bool = false,
) -> MbtProcessHost {
  MbtProcessHost::{
    registry: OpRegistry::new(),
    op_names: [],
    error_policy: CommandErrorPolicy::new(expose_error_details),
    registration_sealed: false,
    closed: false,
  }
}

///|
/// Registers a synchronous MBT-side op.
pub fn[Payload : @json.FromJson, Reply : ToJson] MbtProcessHost::op(
  self : MbtProcessHost,
  name : String,
  callback : (Payload) -> Reply raise?,
) -> Unit raise OpRegistrationError {
  self.ensure_open_for_register()
  self.registry.handle(name, fn(payload) raise { callback(payload) })
  self.op_names.push(name)
}

///|
/// Registers an async MBT-side op.
pub fn[Payload : @json.FromJson, Reply : ToJson] MbtProcessHost::op_async(
  self : MbtProcessHost,
  name : String,
  callback : async (Payload) -> Reply,
) -> Unit raise OpRegistrationError {
  self.ensure_open_for_register()
  self.registry.handle_async(name, callback)
  self.op_names.push(name)
}

///|
/// Registers an async MBT-side op that receives request-scoped context.
pub fn[Payload : @json.FromJson, Reply : ToJson] MbtProcessHost::op_async_with_context(
  self : MbtProcessHost,
  name : String,
  callback : async (AppCommandRequestContext, Payload) -> Reply,
) -> Unit raise OpRegistrationError {
  self.ensure_open_for_register()
  self.registry.handle_async_with_context(name, callback)
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
  let request = request.validate() catch {
    error => {
      complete(
        @ipc.IpcOpResponse::err(
          fallback_id,
          self.error_policy.response_message(error, "invalid command request"),
        ),
      )
      return
    }
  }
  guard !self.closed else {
    complete(
      @ipc.IpcOpResponse::err(request.id, OpDispatchError::HostClosed.message()),
    )
    return
  }
  if self.registry.has_async(request.name) {
    complete(
      @ipc.IpcOpResponse::err(
        request.id,
        OpDispatchError::AsyncHandlerRequiresAsync(name=request.name).message(),
      ),
    )
  } else {
    let response = try self.registry.call(request.name, request.payload) catch {
      error =>
        @ipc.IpcOpResponse::err(request.id, self.dispatch_error_message(error))
    } noraise {
      body => @ipc.IpcOpResponse::ok(request.id, body)
    }
    complete(response)
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
  let request = request.validate() catch {
    error =>
      return @ipc.IpcOpResponse::err(
        fallback_id,
        self.error_policy.response_message(error, "invalid command request"),
      )
  }
  guard !self.closed else {
    return @ipc.IpcOpResponse::err(
      request.id,
      OpDispatchError::HostClosed.message(),
    )
  }
  let body = if self.registry.has_async(request.name) {
    self.registry.call_async_direct(request.name, request.payload) catch {
      error =>
        return @ipc.IpcOpResponse::err(
          request.id,
          self.dispatch_error_message(error),
        )
    }
  } else {
    self.registry.call(request.name, request.payload) catch {
      error =>
        return @ipc.IpcOpResponse::err(
          request.id,
          self.dispatch_error_message(error),
        )
    }
  }
  @ipc.IpcOpResponse::ok(request.id, body)
}

///|
/// Dispatches one decoded IPC request with request-scoped context.
pub async fn MbtProcessHost::dispatch_async_with_context(
  self : MbtProcessHost,
  context : AppCommandRequestContext,
  request : @ipc.IpcOpRequest,
) -> @ipc.IpcOpResponse {
  let fallback_id = ipc_request_fallback_response_id(request)
  let request = request.validate() catch {
    error =>
      return @ipc.IpcOpResponse::err(
        fallback_id,
        self.error_policy.response_message(error, "invalid command request"),
      )
  }
  guard !self.closed else {
    return @ipc.IpcOpResponse::err(
      request.id,
      OpDispatchError::HostClosed.message(),
    )
  }
  let body = self.registry.call_async_direct_with_context(
    context,
    request.name,
    request.payload,
  ) catch {
    error =>
      return @ipc.IpcOpResponse::err(
        request.id,
        self.dispatch_error_message(error),
      )
  }
  @ipc.IpcOpResponse::ok(request.id, body)
}

///|
fn MbtProcessHost::dispatch_error_message(
  self : MbtProcessHost,
  error : Error,
) -> String {
  let safe_message = match error {
    InvalidPayload(name~, ..) => "invalid payload for op " + name
    HandlerFailed(name~, ..) => "op " + name + " failed"
    UnknownOp(name~) => OpDispatchError::UnknownOp(name~).message()
    OpDispatchError::HostClosed => OpDispatchError::HostClosed.message()
    AsyncHandlerRequiresAsync(name~) =>
      OpDispatchError::AsyncHandlerRequiresAsync(name~).message()
    _ => "command dispatch failed"
  }
  self.error_policy.response_message(error, safe_message)
}

///|
/// Parses and dispatches one JSON IPC request payload.
pub fn MbtProcessHost::dispatch_json(
  self : MbtProcessHost,
  raw : String,
  complete : (@ipc.IpcOpResponse) -> Unit,
) -> Unit {
  let request = @ipc.parse_ipc_op_request(raw) catch {
    error => {
      complete(
        @ipc.IpcOpResponse::err(
          "invalid",
          self.error_policy.response_message(error, "invalid command request"),
        ),
      )
      return
    }
  }
  self.dispatch(request, complete)
}

///|
/// Parses and dispatches one JSON IPC request payload on the current async loop.
pub async fn MbtProcessHost::dispatch_json_async(
  self : MbtProcessHost,
  raw : String,
) -> @ipc.IpcOpResponse {
  let request = @ipc.parse_ipc_op_request(raw) catch {
    error =>
      return @ipc.IpcOpResponse::err(
        "invalid",
        self.error_policy.response_message(error, "invalid command request"),
      )
  }
  self.dispatch_async(request)
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
fn MbtProcessHost::ensure_open_for_register(
  self : MbtProcessHost,
) -> Unit raise OpRegistrationError {
  guard !self.closed else { raise OpRegistrationError::HostClosed }
  guard !self.registration_sealed else { raise RegistrationSealed }
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
