///|
/// Command host for user app code.
///
/// The framework decides how this host is connected to the window runtime.
/// App authors register commands and run the host without depending on the
/// underlying IPC implementation.
struct AppCommandHost {
  host : MbtProcessHost
  mut event_sender : (async (@ipc.IpcExtensionEvent) -> Unit)?
  mut scoped_event_sender : (async (@ipc.IpcExtensionEvent) -> Unit)?
  event_scoped_ops : Set[String]
  event_scope_mutex : @async.Mutex
  mut closed : Bool
}

///|
/// Creates an empty app command host.
pub fn AppCommandHost::new() -> AppCommandHost {
  AppCommandHost::{
    host: MbtProcessHost::new(),
    event_sender: None,
    scoped_event_sender: None,
    event_scoped_ops: Set([]),
    event_scope_mutex: @async.Mutex::Mutex(),
    closed: false,
  }
}

///|
/// Registers a synchronous app command.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandHost::op(
  self : AppCommandHost,
  name : String,
  callback : (Payload) -> Reply,
) -> Unit {
  self.host.op(name, callback)
}

///|
/// Registers a synchronous app command that can return a string error.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandHost::op_result(
  self : AppCommandHost,
  name : String,
  callback : (Payload) -> Result[Reply, String],
) -> Unit {
  self.host.op_result(name, callback)
}

///|
/// Registers an async app command.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandHost::op_async(
  self : AppCommandHost,
  name : String,
  callback : async (Payload) -> Reply,
) -> Unit {
  self.host.op_async(name, callback)
}

///|
/// Registers an async app command that can return a string error.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandHost::op_async_result(
  self : AppCommandHost,
  name : String,
  callback : async (Payload) -> Result[Reply, String],
) -> Unit {
  self.host.op_async_result(name, callback)
}

///|
/// Returns registered command names in registration order.
pub fn AppCommandHost::registered_ops(self : AppCommandHost) -> Array[String] {
  self.host.registered_ops()
}

///|
/// Dispatches one IPC request on the current async loop.
pub async fn AppCommandHost::dispatch_ipc(
  self : AppCommandHost,
  request : @ipc.IpcOpRequest,
) -> @ipc.IpcOpResponse {
  self.host.dispatch_async(request)
}

///|
/// Dispatches one IPC request with an event sender scoped to the current async task.
pub async fn AppCommandHost::dispatch_ipc_with_event_sender(
  self : AppCommandHost,
  request : @ipc.IpcOpRequest,
  emit : (async (@ipc.IpcExtensionEvent) -> Unit)?,
) -> @ipc.IpcOpResponse {
  match (emit, self.event_scoped_ops.contains(request.name)) {
    (Some(sender), true) => {
      self.event_scope_mutex.acquire()
      self.scoped_event_sender = Some(sender)
      defer {
        self.scoped_event_sender = None
        self.event_scope_mutex.release()
      }
      self.host.dispatch_async(request)
    }
    (None, _) => self.host.dispatch_async(request)
    (_, false) => self.host.dispatch_async(request)
  }
}

///|
/// Marks an op as emitting extension events during request handling.
pub fn AppCommandHost::scope_events_for_op(
  self : AppCommandHost,
  name : String,
) -> Unit {
  guard !self.closed else { return }
  self.event_scoped_ops.add(name)
}

///|
/// Installs the process-level event sender used by command extensions.
///
/// Events emitted while handling a bridged request use the request-scoped sender
/// installed by `dispatch_ipc_with_event_sender`.
pub fn AppCommandHost::set_event_sender(
  self : AppCommandHost,
  emit : async (@ipc.IpcExtensionEvent) -> Unit,
) -> Unit {
  guard !self.closed else { return }
  self.event_sender = Some(emit)
}

///|
/// Prevents later command registration while keeping existing commands usable.
pub fn AppCommandHost::seal_registrations(self : AppCommandHost) -> Unit {
  guard !self.closed else { return }
  self.host.seal_registrations()
}

///|
/// Emits one extension event through the installed IPC event sender.
pub async fn[Payload : ToJson] AppCommandHost::emit_extension(
  self : AppCommandHost,
  extension_namespace : String,
  event_name : String,
  payload : Payload,
) -> Unit {
  guard !self.closed else { return }
  match validate_extension_event_target(extension_namespace, event_name) {
    Err(error) => abort(error)
    Ok(_) => ()
  }
  let sender = match self.scoped_event_sender {
    Some(emit) => Some(emit)
    None => self.event_sender
  }
  match sender {
    Some(emit) =>
      emit(
        @ipc.IpcExtensionEvent::new(
          extension_namespace,
          event_name,
          ToJson::to_json(payload),
        ),
      )
    None => ()
  }
}

///|
/// Closes this command host and rejects future dispatches.
pub fn AppCommandHost::close(self : AppCommandHost) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  self.event_sender = None
  self.host.close()
}
