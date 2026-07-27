///|
/// Command host for user app code.
///
/// The framework decides how this host is connected to the window runtime.
/// App authors register commands and run the host without depending on the
/// underlying IPC implementation.
struct AppCommandHost {
  host : MbtProcessHost
  mut event_sender : (async (@ipc.IpcExtensionEvent) -> Unit noraise)?
  mut scoped_event_sender : (async (@ipc.IpcExtensionEvent) -> Unit noraise)?
  event_scoped_ops : Set[String]
  event_scope_mutex : @async.Mutex
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
  wake_signal : RuntimeWakeSignal
}

///|
pub fn AppCommandRequestContext::new(
  window : Int64,
  wake_signal? : RuntimeWakeSignal = RuntimeWakeSignal::new(),
) -> AppCommandRequestContext {
  AppCommandRequestContext::{ window, wake_signal }
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
/// Dispatches one IPC request with an event sender scoped to the current async task.
pub async fn AppCommandHost::dispatch_ipc_with_event_sender(
  self : AppCommandHost,
  request : @ipc.IpcOpRequest,
  emit : (async (@ipc.IpcExtensionEvent) -> Unit noraise)?,
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
/// Dispatches one IPC request with request-scoped context and a scoped event sender.
pub async fn AppCommandHost::dispatch_ipc_with_context_and_event_sender(
  self : AppCommandHost,
  context : AppCommandRequestContext,
  request : @ipc.IpcOpRequest,
  emit : (async (@ipc.IpcExtensionEvent) -> Unit noraise)?,
) -> @ipc.IpcOpResponse {
  match (emit, self.event_scoped_ops.contains(request.name)) {
    (Some(sender), true) => {
      self.event_scope_mutex.acquire()
      self.scoped_event_sender = Some(sender)
      defer {
        self.scoped_event_sender = None
        self.event_scope_mutex.release()
      }
      self.host.dispatch_async_with_context(context, request)
    }
    (None, _) => self.host.dispatch_async_with_context(context, request)
    (_, false) => self.host.dispatch_async_with_context(context, request)
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
  emit : async (@ipc.IpcExtensionEvent) -> Unit noraise,
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
) -> Unit noraise {
  guard !self.closed else { return }
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
