///|
/// Command host for user app code.
///
/// The framework decides how this host is connected to the window runtime.
/// App authors register commands and run the host without depending on the
/// underlying IPC implementation.
struct AppCommandHost {
  host : MbtProcessHost
  mut event_sender : (async (@ipc.IpcExtensionEvent) -> Unit)?
  mut closed : Bool
}

///|
/// Creates an empty app command host.
pub fn AppCommandHost::new() -> AppCommandHost {
  AppCommandHost::{
    host: MbtProcessHost::new(),
    event_sender: None,
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
/// Installs the process-level event sender used by command extensions.
///
/// The sender is intentionally not request-scoped: extension events are
/// broadcast notifications and may be emitted after the triggering op returns.
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
  match self.event_sender {
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
