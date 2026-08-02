///|
/// Command host for user app code.
///
/// The framework decides how this host is connected to the window runtime.
/// App authors register commands and run the host without depending on the
/// underlying IPC implementation.
struct AppCommandHost {
  host : MbtProcessHost
  mut closed : Bool
}

///|
/// Scheduler-local notification shared by the runtime pump and command tasks.
/// The revision makes waiting race-free when a notification arrives between a
/// native poll and suspension on the condition variable.
pub struct RuntimeWakeSignal {
  mut revision : Int64
  condition : @async.CondVar
}

///|
pub fn RuntimeWakeSignal::new() -> RuntimeWakeSignal {
  RuntimeWakeSignal::{ revision: 0L, condition: @async.CondVar::Cond() }
}

///|
pub fn RuntimeWakeSignal::revision(self : RuntimeWakeSignal) -> Int64 {
  self.revision
}

///|
pub fn RuntimeWakeSignal::notify(self : RuntimeWakeSignal) -> Unit {
  self.revision = self.revision + 1L
  self.condition.broadcast()
}

///|
pub async fn RuntimeWakeSignal::wait_for_change(
  self : RuntimeWakeSignal,
  revision : Int64,
) -> Unit {
  while self.revision == revision {
    self.condition.wait()
  }
}

///|
/// Request-scoped context for one bridged app command dispatch.
pub struct AppCommandRequestContext {
  window : Int64
  window_id : String
  source_origin : String
  page_instance : String?
  permission_extension : String?
  permission_scope_value : Json?
  tasks : @async.TaskGroup[Unit]
  wake_signal : RuntimeWakeSignal
  emit_event : async (@proton_contract.ContractRoute, String, Json) -> Unit noraise
}

///|
#doc(hidden)
pub fn AppCommandRequestContext::new(
  window : Int64,
  tasks : @async.TaskGroup[Unit],
  window_id? : String = "main",
  source_origin? : String = "app",
  page_instance? : String? = None,
  permission_extension? : String,
  permission_scope? : Json,
  wake_signal? : RuntimeWakeSignal = RuntimeWakeSignal::new(),
  emit_event? : async (@proton_contract.ContractRoute, String, Json) -> Unit noraise = fn(
    _route,
    _name,
    _payload,
  ) {

  },
) -> AppCommandRequestContext {
  AppCommandRequestContext::{
    window,
    window_id,
    source_origin,
    page_instance,
    permission_extension,
    permission_scope_value: permission_scope.map(clone_permission_json),
    tasks,
    wake_signal,
    emit_event,
  }
}

///|
pub fn AppCommandRequestContext::wake_signal(
  self : AppCommandRequestContext,
) -> RuntimeWakeSignal {
  self.wake_signal
}

///|
pub fn AppCommandRequestContext::wake_revision(
  self : AppCommandRequestContext,
) -> Int64 {
  self.wake_signal.revision()
}

///|
pub async fn AppCommandRequestContext::wait_for_wake(
  self : AppCommandRequestContext,
  revision : Int64,
) -> Unit {
  self.wake_signal.wait_for_change(revision)
}

///|
pub fn AppCommandRequestContext::window(
  self : AppCommandRequestContext,
) -> Int64 {
  self.window
}

///|
pub fn AppCommandRequestContext::window_id(
  self : AppCommandRequestContext,
) -> String {
  self.window_id
}

///|
pub fn AppCommandRequestContext::source_origin(
  self : AppCommandRequestContext,
) -> String {
  self.source_origin
}

///|
/// Returns the renderer page instance that issued this request, when the
/// context came from the native bridge.
pub fn AppCommandRequestContext::page_instance(
  self : AppCommandRequestContext,
) -> String? {
  self.page_instance
}

///|
/// Returns this request's extension-specific permission scope.
pub fn AppCommandRequestContext::permission_scope(
  self : AppCommandRequestContext,
  extension_id : String,
) -> Json raise CommandPermissionError {
  match (self.permission_extension, self.permission_scope_value) {
    (Some(actual), Some(scope)) if actual == extension_id =>
      clone_permission_json(scope)
    (Some(actual), _) => raise Foreign(expected=extension_id, actual~)
    _ => raise Missing(extension_id~)
  }
}

///|
fn clone_permission_json(value : Json) -> Json {
  match value {
    Array(items) => Json::array(items.map(clone_permission_json))
    Object(object) => {
      let copy : Map[String, Json] = Map([])
      for key, item in object {
        copy[key] = clone_permission_json(item)
      }
      Json::object(copy)
    }
    _ => value
  }
}

///|
/// Returns the task group owned by this command lifecycle.
///
/// Child tasks are cancelled and joined when the issuing window closes.
pub fn AppCommandRequestContext::task_group(
  self : AppCommandRequestContext,
) -> @async.TaskGroup[Unit] {
  self.tasks
}

///|
/// Emits a typed event to the renderer page that issued this command.
pub async fn[Payload : ToJson] AppCommandRequestContext::emit(
  self : AppCommandRequestContext,
  event : @proton_contract.Event[Payload],
  payload : Payload,
) -> Unit {
  event.validate()
  (self.emit_event)(
    event.contract_route(),
    event.name(),
    ToJson::to_json(payload),
  )
}

///|
/// Creates an empty app command host.
///
/// Handler diagnostics remain in backend logs by default. Set
/// `expose_error_details` only for a trusted development frontend.
pub fn AppCommandHost::new(
  expose_error_details? : Bool = false,
) -> AppCommandHost {
  AppCommandHost::{
    host: MbtProcessHost::new(expose_error_details~),
    closed: false,
  }
}

///|
/// Registers a synchronous app command.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandHost::op(
  self : AppCommandHost,
  name : String,
  callback : (Payload) -> Reply raise?,
) -> Unit raise OpRegistrationError {
  self.host.op(name, fn(payload) raise { callback(payload) })
}

///|
/// Registers an async app command.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandHost::op_async(
  self : AppCommandHost,
  name : String,
  callback : async (Payload) -> Reply,
) -> Unit raise OpRegistrationError {
  self.host.op_async(name, callback)
}

///|
/// Registers an async app command that receives request-scoped context.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandHost::op_async_with_context(
  self : AppCommandHost,
  name : String,
  callback : async (AppCommandRequestContext, Payload) -> Reply,
) -> Unit raise OpRegistrationError {
  self.host.op_async_with_context(name, callback)
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
/// Dispatches one IPC request with request-scoped context.
pub async fn AppCommandHost::dispatch_ipc_with_context(
  self : AppCommandHost,
  context : AppCommandRequestContext,
  request : @ipc.IpcOpRequest,
) -> @ipc.IpcOpResponse {
  self.host.dispatch_async_with_context(context, request)
}

///|
/// Prevents later command registration while keeping existing commands usable.
pub fn AppCommandHost::seal_registrations(self : AppCommandHost) -> Unit {
  guard !self.closed else { return }
  self.host.seal_registrations()
}

///|
/// Closes this command host and rejects future dispatches.
pub fn AppCommandHost::close(self : AppCommandHost) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  self.host.close()
}
