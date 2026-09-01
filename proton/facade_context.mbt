///|
/// Application-lifetime capabilities supplied to startup hooks.
pub struct ApplicationContext {
  tasks : @async.TaskGroup[Unit]
  windows : WindowManager
  locale_preferences : @locale.LocalePreferences
  request_quit : () -> Unit
  application_identifier : String
  application_executable : String
  application_arguments : Array[String]
  url_schemes : Array[String]
}

///|
/// Window-lifetime capabilities supplied to window startup hooks.
pub struct WindowContext {
  id : String
  handle : WindowHandle
  windows : WindowManager
  tasks : @async.TaskGroup[Unit]
  events : WindowEventEmitter
  locale_preferences : @locale.LocalePreferences
}

///|
/// A typed event destination bound to one explicit window.
pub struct WindowEventEmitter {
  emit_event : async (@proton_contract.ContractRoute, String, Json) -> Unit noraise
}

///|
priv struct ApplicationLifecycleActivation {
  shutdown : async () -> Unit
}

///|
priv struct ApplicationLifecycleHook {
  start : async (ApplicationContext) -> ApplicationLifecycleActivation
}

///|
priv struct WindowLifecycleActivation {
  close : async () -> Unit
}

///|
priv struct WindowLifecycleHook {
  start : async (WindowContext) -> WindowLifecycleActivation
}

///|
fn ApplicationContext::ApplicationContext(
  tasks : @async.TaskGroup[Unit],
  windows : WindowManager,
  locale_preferences : @locale.LocalePreferences,
  request_quit? : () -> Unit = fn() {  },
  application_identifier? : String = "",
  application_executable? : String = "",
  application_arguments? : Array[String] = [],
  url_schemes? : Array[String] = [],
) -> ApplicationContext {
  ApplicationContext::{
    tasks,
    windows,
    locale_preferences,
    request_quit,
    application_identifier,
    application_executable,
    application_arguments,
    url_schemes,
  }
}

///|
fn WindowContext::WindowContext(
  id : String,
  handle : WindowHandle,
  windows : WindowManager,
  tasks : @async.TaskGroup[Unit],
  events : WindowEventEmitter,
  locale_preferences : @locale.LocalePreferences,
) -> WindowContext {
  WindowContext::{ id, handle, windows, tasks, events, locale_preferences, }
}

///|
/// Returns the immutable application locale selected at startup.
pub fn ApplicationContext::locale(self : ApplicationContext) -> @locale.Locale {
  self.locale_preferences.locale()
}

///|
/// Returns the application's ordered language preferences.
pub fn ApplicationContext::preferred_languages(
  self : ApplicationContext,
) -> Array[@locale.Locale] {
  self.locale_preferences.preferred_languages()
}

///|
/// Returns the immutable application locale selected at startup.
pub fn WindowContext::locale(self : WindowContext) -> @locale.Locale {
  self.locale_preferences.locale()
}

///|
/// Returns the application's ordered language preferences.
pub fn WindowContext::preferred_languages(
  self : WindowContext,
) -> Array[@locale.Locale] {
  self.locale_preferences.preferred_languages()
}

///|
/// Returns the declarative id of this window. The primary window uses
/// `"main"`.
pub fn WindowContext::id(self : WindowContext) -> String {
  self.id
}

///|
fn WindowEventEmitter::WindowEventEmitter(
  emit_event : async (@proton_contract.ContractRoute, String, Json) -> Unit noraise,
) -> WindowEventEmitter {
  WindowEventEmitter::{ emit_event, }
}

///|
/// Returns the structured task group owned by this application.
pub fn ApplicationContext::task_group(
  self : ApplicationContext,
) -> @async.TaskGroup[Unit] {
  self.tasks
}

///|
/// Returns the window manager owned by this running application.
pub fn ApplicationContext::windows(self : ApplicationContext) -> WindowManager {
  self.windows
}

///|
/// Requests an orderly application shutdown.
///
/// Proton closes every open window, runs configured close interception, and
/// destroys the native runtime after all windows have closed. A denied window
/// close cancels this quit request.
pub fn ApplicationContext::quit(self : ApplicationContext) -> Unit {
  (self.request_quit)()
}

///|
fn ApplicationContext::protocol_client_values(
  self : ApplicationContext,
  scheme : String,
  executable : String?,
) -> (String, String) raise AppControlError {
  let scheme = scheme.trim().to_owned().to_lower()
  guard app_url_scheme_is_valid(scheme) else {
    raise InvalidProtocolScheme(scheme~)
  }
  guard self.url_schemes.contains(scheme) else {
    raise UndeclaredProtocolScheme(scheme~)
  }
  let executable = executable.unwrap_or(self.application_executable)
  guard executable.trim().to_owned() != "" else {
    raise InvalidExecutable(path=executable)
  }
  (scheme, executable)
}

///|
fn app_control_native_error(
  action : String,
  error : @native.NativeError,
) -> AppControlError {
  NativeControlFailure(action~, status=error.status(), detail=error.message())
}

///|
/// Sets this application as the default handler for a declared URL scheme.
///
/// `executable` and `arguments` match Electron's Windows-only command
/// override. Other platforms use the packaged application identity.
pub fn ApplicationContext::set_as_default_protocol_client(
  self : ApplicationContext,
  scheme : String,
  executable? : String,
  arguments? : Array[String] = [],
) -> Bool raise AppControlError {
  let (scheme, executable) = self.protocol_client_values(scheme, executable)
  @native.protocol_client_set(
    scheme,
    self.application_identifier,
    executable,
    arguments,
  ) catch {
    error =>
      raise app_control_native_error("set default protocol client", error)
  }
}

///|
/// Removes this application as the default handler for a declared URL scheme.
///
/// Electron exposes removal on macOS and Windows. Linux returns `false`.
pub fn ApplicationContext::remove_default_protocol_client(
  self : ApplicationContext,
  scheme : String,
  executable? : String,
  arguments? : Array[String] = [],
) -> Bool raise AppControlError {
  let (scheme, executable) = self.protocol_client_values(scheme, executable)
  @native.protocol_client_remove(
    scheme,
    self.application_identifier,
    executable,
    arguments,
  ) catch {
    error =>
      raise app_control_native_error("remove default protocol client", error)
  }
}

///|
/// Reports whether this application handles a declared URL scheme by default.
pub fn ApplicationContext::is_default_protocol_client(
  self : ApplicationContext,
  scheme : String,
  executable? : String,
  arguments? : Array[String] = [],
) -> Bool raise AppControlError {
  let (scheme, executable) = self.protocol_client_values(scheme, executable)
  @native.protocol_client_is_default(
    scheme,
    self.application_identifier,
    executable,
    arguments,
  ) catch {
    error =>
      raise app_control_native_error("query default protocol client", error)
  }
}

///|
/// Schedules a new application instance after the current instance exits.
///
/// Calling this method multiple times schedules multiple instances. It does
/// not quit the current application; call `quit` or `exit` separately.
pub fn ApplicationContext::relaunch(
  self : ApplicationContext,
  options? : RelaunchOptions,
) -> Unit raise AppControlError {
  let (executable, arguments) = self.relaunch_command(options)
  @native.process_schedule_relaunch(executable, arguments) catch {
    error =>
      raise app_control_native_error("schedule application relaunch", error)
  }
}

///|
fn ApplicationContext::relaunch_command(
  self : ApplicationContext,
  options : RelaunchOptions?,
) -> (String, Array[String]) raise AppControlError {
  let (executable, arguments) = match options {
    None => (self.application_executable, self.application_arguments.copy())
    Some({ executable: None, arguments: None, }) =>
      (self.application_executable, self.application_arguments.copy())
    Some(options) =>
      (
        options.executable.unwrap_or(self.application_executable),
        options.arguments.unwrap_or([]),
      )
  }
  guard executable.trim().to_owned() != "" else {
    raise InvalidExecutable(path=executable)
  }
  (executable, arguments)
}

///|
/// Immediately terminates the process with `exit_code`.
///
/// This skips window close interception and lifecycle shutdown hooks. Any
/// relaunches already scheduled through `relaunch` are started first.
pub fn ApplicationContext::exit(
  self : ApplicationContext,
  exit_code? : Int = 0,
) -> Unit {
  ignore(self)
  @native.process_exit(exit_code)
}

///|
/// Returns the session-controlled handle for this concrete window instance.
pub fn WindowContext::handle(self : WindowContext) -> WindowHandle {
  self.handle
}

///|
/// Returns the application window manager.
pub fn WindowContext::windows(self : WindowContext) -> WindowManager {
  self.windows
}

///|
/// Returns the structured task group owned by this window.
pub fn WindowContext::task_group(
  self : WindowContext,
) -> @async.TaskGroup[Unit] {
  self.tasks
}

///|
/// Returns an event emitter bound to this window's active page.
pub fn WindowContext::events(self : WindowContext) -> WindowEventEmitter {
  self.events
}

///|
/// Emits a typed event to this emitter's window.
pub async fn[Payload : ToJson] WindowEventEmitter::emit(
  self : WindowEventEmitter,
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
async fn start_application_lifecycle_hooks(
  hooks : Array[ApplicationLifecycleHook],
  context : ApplicationContext,
  group : @async.TaskGroup[Unit],
  cleanup_failures : Array[AppCleanupError],
) -> Unit raise AppRunError {
  for index, hook in hooks {
    let activation = (hook.start)(context) catch {
      error =>
        raise LifecycleHookError(
          ApplicationStart(index~, detail=@debug.render(Repr(error))),
        )
    }
    group.add_defer(async fn() {
      @async.protect_from_cancel(activation.shutdown) catch {
        error =>
          cleanup_failures.push(
            LifecycleHook(
              ApplicationShutdown(index~, detail=@debug.render(Repr(error))),
            ),
          )
      }
    })
  }
}

///|
async fn start_window_lifecycle_hooks(
  hooks : Array[WindowLifecycleHook],
  context : WindowContext,
  group : @async.TaskGroup[Unit],
  cleanup_failures : Array[AppCleanupError],
) -> Unit raise AppRunError {
  for index, hook in hooks {
    let activation = (hook.start)(context) catch {
      error =>
        raise LifecycleHookError(
          WindowReady(index~, detail=@debug.render(Repr(error))),
        )
    }
    group.add_defer(async fn() {
      @async.protect_from_cancel(activation.close) catch {
        error =>
          cleanup_failures.push(
            LifecycleHook(
              WindowClose(index~, detail=@debug.render(Repr(error))),
            ),
          )
      }
    })
  }
}
