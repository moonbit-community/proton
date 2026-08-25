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
/// Window-scoped application capabilities available to one command request.
/// The native window identity and implementation remain owned by the Proton
/// runtime; extensions can only invoke these semantic operations.
pub struct CommandWindow {
  show_message_dialog : async (String?, String, String) -> Unit
  show_confirm_dialog : async (String?, String, String) -> Bool
  open_file_dialog : async (String?, String?) -> String?
  save_file_dialog : async (String?, String?) -> String?
  choose_directory_dialog : async (String?, String?) -> String?
}

///|
#doc(hidden)
pub fn CommandWindow::CommandWindow(
  show_message_dialog : async (String?, String, String) -> Unit,
  show_confirm_dialog : async (String?, String, String) -> Bool,
  open_file_dialog : async (String?, String?) -> String?,
  save_file_dialog : async (String?, String?) -> String?,
  choose_directory_dialog : async (String?, String?) -> String?,
) -> CommandWindow {
  {
    show_message_dialog,
    show_confirm_dialog,
    open_file_dialog,
    save_file_dialog,
    choose_directory_dialog,
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
pub fn RuntimeWakeSignal::RuntimeWakeSignal() -> RuntimeWakeSignal {
  RuntimeWakeSignal::{ revision: 0L, condition: @async.CondVar::Cond() }
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
/// Set `diagnostic_reporter` to retain backend-only handler diagnostics. Set
/// `expose_error_details` only for a trusted development frontend.
pub fn AppCommandHost::AppCommandHost(
  expose_error_details? : Bool = false,
  diagnostic_reporter? : (String) -> Unit = ignore_command_diagnostic,
) -> AppCommandHost {
  AppCommandHost::new_with_diagnostic_reporter(
    expose_error_details, diagnostic_reporter,
  )
}

///|
fn AppCommandHost::new_with_diagnostic_reporter(
  expose_error_details : Bool,
  report_diagnostic : (String) -> Unit,
) -> AppCommandHost {
  AppCommandHost::{
    host: MbtProcessHost::new_with_diagnostic_reporter(
      expose_error_details, report_diagnostic,
    ),
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
