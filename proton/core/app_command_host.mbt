///|
/// Scheduler-local notification shared by the runtime pump and command tasks.
/// The revision makes waiting race-free when a notification arrives between a
/// native poll and suspension on the condition variable.
pub struct RuntimeWakeSignal {
  mut revision : Int64
  condition : @async.CondVar
}

///|
/// Window-scoped application capabilities available to one command request.
/// The native window identity and implementation remain owned by the Proton
/// runtime; extensions can only invoke these semantic operations.
pub struct CommandWindow {
  show_message_dialog : async (String?, String, String) -> Unit
  show_confirm_dialog : async (String?, String, String) -> Bool
  open_file_dialog : async (String?, String?) -> String?
  save_file_dialog : async (String?, String?) -> String?
  choose_directory_dialog : async (String?, String?) -> String?
  get_titlebar_area : () -> Json raise
}

///|
#doc(hidden)
pub fn CommandWindow::CommandWindow(
  show_message_dialog : async (String?, String, String) -> Unit,
  show_confirm_dialog : async (String?, String, String) -> Bool,
  open_file_dialog : async (String?, String?) -> String?,
  save_file_dialog : async (String?, String?) -> String?,
  choose_directory_dialog : async (String?, String?) -> String?,
  get_titlebar_area? : () -> Json raise = fn() { Json::null() },
) -> CommandWindow {
  {
    show_message_dialog,
    show_confirm_dialog,
    open_file_dialog,
    save_file_dialog,
    choose_directory_dialog,
    get_titlebar_area,
  }
}

///|
pub async fn CommandWindow::show_message(
  self : CommandWindow,
  title : String?,
  message : String,
  level : String,
) -> Unit {
  (self.show_message_dialog)(title, message, level)
}

///|
pub async fn CommandWindow::confirm(
  self : CommandWindow,
  title : String?,
  message : String,
  level : String,
) -> Bool {
  (self.show_confirm_dialog)(title, message, level)
}

///|
pub async fn CommandWindow::open_file(
  self : CommandWindow,
  title : String?,
  path : String?,
) -> String? {
  (self.open_file_dialog)(title, path)
}

///|
pub async fn CommandWindow::save_file(
  self : CommandWindow,
  title : String?,
  path : String?,
) -> String? {
  (self.save_file_dialog)(title, path)
}

///|
pub async fn CommandWindow::choose_directory(
  self : CommandWindow,
  title : String?,
  path : String?,
) -> String? {
  (self.choose_directory_dialog)(title, path)
}

///|
#doc(hidden)
pub fn CommandWindow::titlebar_area(self : CommandWindow) -> Json raise {
  (self.get_titlebar_area)()
}

///|
pub fn RuntimeWakeSignal::RuntimeWakeSignal() -> RuntimeWakeSignal {
  RuntimeWakeSignal::{ revision: 0L, condition: @async.CondVar::Cond(), }
}

///|
fn detached_locale_preferences() -> @locale.LocalePreferences {
  @locale.LocalePreferences::resolve(None, [])
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
  window : CommandWindow?
  window_id : String
  source_origin : String
  page_instance : String?
  permission_extension : String?
  permission_scope_value : Json?
  tasks : @async.TaskGroup[Unit]
  wake_signal : RuntimeWakeSignal
  emit_event : async (@proton_contract.ContractRoute, String, Json) -> Unit noraise
  locale_preferences : @locale.LocalePreferences
}

///|
#doc(hidden)
pub fn AppCommandRequestContext::AppCommandRequestContext(
  tasks : @async.TaskGroup[Unit],
  locale_preferences : @locale.LocalePreferences,
  window? : CommandWindow,
  window_id? : String = "main",
  source_origin? : String = "app",
  page_instance? : String? = None,
  permission_extension? : String,
  permission_scope? : Json,
  wake_signal? : RuntimeWakeSignal = RuntimeWakeSignal(),
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
    locale_preferences,
  }
}

///|
/// Builds a request context that is not attached to an application session.
#doc(hidden)
pub fn AppCommandRequestContext::detached(
  tasks : @async.TaskGroup[Unit],
  window_id? : String = "main",
  source_origin? : String = "app",
  page_instance? : String? = None,
  permission_extension? : String,
  permission_scope? : Json,
  wake_signal? : RuntimeWakeSignal = RuntimeWakeSignal(),
  emit_event? : async (@proton_contract.ContractRoute, String, Json) -> Unit noraise = fn(
    _route,
    _name,
    _payload,
  ) {

  },
) -> AppCommandRequestContext {
  AppCommandRequestContext(
    tasks,
    detached_locale_preferences(),
    window_id~,
    source_origin~,
    page_instance~,
    permission_extension?,
    permission_scope?,
    wake_signal~,
    emit_event~,
  )
}

///|
/// Returns the immutable application locale selected at startup.
pub fn AppCommandRequestContext::locale(
  self : AppCommandRequestContext,
) -> @locale.Locale {
  self.locale_preferences.locale()
}

///|
/// Returns the application's ordered language preferences.
pub fn AppCommandRequestContext::preferred_languages(
  self : AppCommandRequestContext,
) -> Array[@locale.Locale] {
  self.locale_preferences.preferred_languages()
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
) -> CommandWindow? {
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
#alias(emit)
pub async fn[Payload : ToJson] AppCommandRequestContext::emit_to_caller(
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
priv struct CommandErrorPolicy {
  expose_details : Bool
  report_diagnostic : (String) -> Unit
}

///|
fn CommandErrorPolicy::CommandErrorPolicy(
  expose_details : Bool,
  report_diagnostic : (String) -> Unit,
) -> CommandErrorPolicy {
  CommandErrorPolicy::{ expose_details, report_diagnostic, }
}

///|
fn CommandErrorPolicy::response_error(
  self : CommandErrorPolicy,
  error : Error,
  code : String,
  safe_message : String,
) -> @ipc.IpcCommandError {
  let diagnostic = @debug.render(Repr(error))
  (self.report_diagnostic)(diagnostic)
  {
    code,
    message: safe_message,
    detail: if self.expose_details {
      Some(diagnostic)
    } else {
      None
    },
  }
}

///|
fn ignore_command_diagnostic(_diagnostic : String) -> Unit {
  ()
}

///|
/// Transport-independent command registration and dispatch.
///
/// The Proton facade runs this host in the application process on the runtime
/// owner thread. Async command handlers use the application async event loop.
#alias(MbtProcessHost)
struct AppCommandHost {
  registry : OpRegistry
  error_policy : CommandErrorPolicy
  mut registration_sealed : Bool
  mut closed : Bool
}

///|
/// Creates an empty command host.
///
/// Set `diagnostic_reporter` to retain backend-only handler diagnostics. Set
/// `expose_error_details` only for a trusted development frontend.
#alias(MbtProcessHost)
pub fn AppCommandHost::AppCommandHost(
  expose_error_details? : Bool = false,
  diagnostic_reporter? : (String) -> Unit = ignore_command_diagnostic,
) -> AppCommandHost {
  AppCommandHost::{
    registry: OpRegistry(),
    error_policy: CommandErrorPolicy(expose_error_details, diagnostic_reporter),
    registration_sealed: false,
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
  self.ensure_open_for_register()
  self.registry.handle(name, fn(payload) raise { callback(payload) })
}

///|
/// Registers an async app command.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandHost::op_async(
  self : AppCommandHost,
  name : String,
  callback : async (Payload) -> Reply,
) -> Unit raise OpRegistrationError {
  self.ensure_open_for_register()
  self.registry.handle_async(name, callback)
}

///|
/// Registers an async app command that receives request-scoped context.
pub fn[Payload : @json.FromJson, Reply : ToJson] AppCommandHost::op_async_with_context(
  self : AppCommandHost,
  name : String,
  callback : async (AppCommandRequestContext, Payload) -> Reply,
) -> Unit raise OpRegistrationError {
  self.ensure_open_for_register()
  self.registry.handle_async_with_context(name, callback)
}

///|
/// Returns registered command names in registration order.
pub fn AppCommandHost::registered_ops(self : AppCommandHost) -> Array[String] {
  self.registry.handlers.keys().to_array()
}

///|
/// Dispatches one decoded IPC request on the current async loop.
#alias(dispatch_async)
pub async fn AppCommandHost::dispatch_ipc(
  self : AppCommandHost,
  request : @ipc.IpcOpRequest,
) -> @ipc.IpcOpResponse {
  self.dispatch(request, None)
}

///|
/// Dispatches one IPC request with request-scoped context.
#alias(dispatch_async_with_context)
pub async fn AppCommandHost::dispatch_ipc_with_context(
  self : AppCommandHost,
  context : AppCommandRequestContext,
  request : @ipc.IpcOpRequest,
) -> @ipc.IpcOpResponse {
  self.dispatch(request, Some(context))
}

///|
async fn AppCommandHost::dispatch(
  self : AppCommandHost,
  request : @ipc.IpcOpRequest,
  context : AppCommandRequestContext?,
) -> @ipc.IpcOpResponse {
  let fallback_id = ipc_request_fallback_response_id(request)
  let request = request.validate() catch {
    error =>
      return @ipc.IpcOpResponse::err(
        fallback_id,
        self.error_policy.response_error(
          error, "invalid_request", "invalid command request",
        ),
      )
  }
  guard !self.closed else {
    return @ipc.IpcOpResponse::err(
      request.id,
      self.dispatch_error(OpDispatchError::HostClosed),
    )
  }
  let body = self.registry.call(request.name, request.payload, context) catch {
    error =>
      return @ipc.IpcOpResponse::err(request.id, self.dispatch_error(error))
  }
  @ipc.IpcOpResponse::ok(request.id, body)
}

///|
fn AppCommandHost::dispatch_error(
  self : AppCommandHost,
  error : Error,
) -> @ipc.IpcCommandError {
  let (code, message) = match error {
    InvalidPayload(name~, ..) =>
      ("invalid_payload", "invalid payload for op " + name)
    HandlerFailed(name~, ..) => ("handler_failed", "op " + name + " failed")
    UnknownOp(name~) =>
      ("unknown_op", OpDispatchError::UnknownOp(name~).message())
    OpDispatchError::HostClosed =>
      ("host_closed", OpDispatchError::HostClosed.message())
    AsyncHandlerRequiresAsync(name~) =>
      (
        "async_dispatch_required",
        OpDispatchError::AsyncHandlerRequiresAsync(name~).message(),
      )
    RequestContextRequired(name~) =>
      (
        "request_context_required",
        OpDispatchError::RequestContextRequired(name~).message(),
      )
    _ => ("dispatch_failed", "command dispatch failed")
  }
  self.error_policy.response_error(error, code, message)
}

///|
/// Prevents later command registration while keeping existing commands usable.
pub fn AppCommandHost::seal_registrations(self : AppCommandHost) -> Unit {
  guard !self.closed else { return }
  self.registration_sealed = true
}

///|
/// Closes this host and rejects future dispatches.
pub fn AppCommandHost::close(self : AppCommandHost) -> Unit {
  guard !self.closed else { return }
  self.closed = true
}

///|
fn AppCommandHost::ensure_open_for_register(
  self : AppCommandHost,
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
