///|
/// High-level application facade for ordinary Proton apps.
struct App {
  file_path : String?
  auto_config : Bool
  mut window : @manifest.WindowManifest
  mut entry : @manifest.AppEntry
  windows : Array[@manifest.AppWindowManifest]
  mut debug_level_value : Int
  mut headless_value : Bool
  mut single_instance_identifier : String?
  mut title_overridden : Bool
  mut size_overridden : Bool
  mut titlebar_style_overridden : Bool
  mut entry_overridden : Bool
  mut debug_overridden : Bool
  mut bridge_startup_timeout_value_ms : Int
  mut menu : @native.MenuBar?
  extension_settings : Map[String, @manifest.ExtensionSetting]
  permission_grants : Array[@manifest.PermissionGrant]
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec]
  command_registrars : Array[(@proton_command.CommandRegistrar) -> Unit raise]
  application_lifecycle_hooks : Array[ApplicationLifecycleHook]
  launch_input_handlers : Array[async (RuntimeLaunchInput) -> Unit noraise]
  window_event_handlers : Array[
    async (WindowHandle, WindowEvent) -> Unit noraise,
  ]
  mut window_close_handler : (async (WindowHandle) -> WindowCloseDecision noraise)?
  mut navigation_handler : (async (BrowserHandle, NavigationRequest) -> NavigationDecision noraise)?
  mut popup_handler : (async (BrowserHandle, PopupRequest) -> PopupDecision noraise)?
  mut download_handler : (async (BrowserHandle, DownloadRequest) -> DownloadDecision noraise)?
  mut certificate_handler : (async (BrowserHandle, CertificateError) -> BrowserPermissionDecision noraise)?
  mut media_handler : (async (BrowserHandle, MediaPermissionRequest) -> BrowserPermissionDecision noraise)?
  download_event_handlers : Array[
    async (BrowserHandle, DownloadEvent) -> Unit noraise,
  ]
  update_handlers : Array[async (PendingUpdate) -> Unit noraise]
  window_lifecycle_hooks : Array[WindowLifecycleHook]
  validation_errors : Array[AppConfigurationError]
}

///|
let default_bridge_startup_timeout_ms = 30000

///|
priv struct ResolvedAppConfig {
  manifest : @manifest.AppManifest
  permission_base_path : String
  instance_identifier : String?
  url_schemes : Array[String]
  document_extensions : Array[String]
  /// The update channel and the identity it updates, when `moon.proton`
  /// declares one. Absent for an application configured inline: there is no
  /// file to declare an endpoint in, and inventing one would be worse.
  update_channel : ResolvedUpdateChannel?
}

///|
priv struct ResolvedUpdateChannel {
  config : @bootstrap.ProtonUpdaterConfig
}

///|
priv struct BridgeDispatchTask {
  request_id : Int64
  window : Int64
  task : @async.Task[@native.BridgeResponse]
  mut state : BridgeRequestLifecycleState
}

///|
priv struct RunningWindow {
  id : String
  window : @native.Window
  permissions : WindowPermissionPolicy
  lifetime : WindowLifetime
  views : Array[RunningView]
  mut bridge_ready : Bool
  mut state : SessionWindowState
}

///|
priv struct RunningView {
  id : String
  view : @native.View
}

///|
priv enum SessionWindowState {
  WindowStarting = 0
  WindowOpen = 1
  WindowCloseRequested = 2
  WindowClosed = 3
}

///|
priv struct WindowLifetime {
  mut ready : Bool
  mut closed : Bool
  mut startup_error : AppRunError?
  ready_signal : @async.CondVar
  close_signal : @async.CondVar
}

///|
priv struct PlannedWindow {
  id : String
  window : @manifest.WindowManifest
  entry : @manifest.AppEntry
  open_on_start : Bool
}

///|
priv struct PreparedWindow {
  plan : PlannedWindow
  bridge : @native.BridgeConfig?
  permissions : WindowPermissionPolicy
  browser_policy : @native.BrowserPolicy
}

///|
priv struct CommandHostRuntime {
  host : @core.AppCommandHost
  destroy_hooks : Array[CommandExtensionDestroyHook]
  mut closed : Bool
}

///|
priv struct CommandExtensionDestroyHook {
  extension_id : String
  callback : () -> Unit raise
}

///|
priv struct BridgePagePolicy {
  entry_origin : String?
}

///|
priv struct BridgeFrontendConfig {
  extensions : Array[@native.BridgeExtensionConfig]
  initialization_units : Array[@native.BridgeInitializationUnit]
}

///|
priv struct ResolvedPermissionGrant {
  source_origin : String
  extension_id : String
  ops : Array[String]
  scope : Json
}

///|
priv struct WindowPermissionPolicy {
  grants : Array[ResolvedPermissionGrant]
}

///|
/// Owns the mutable state of one running Proton application.
///
/// Native window ownership stays in this session. Public window references
/// are non-owning capabilities that route operations back through the session
/// instead of duplicating native lifecycle state.
priv struct RuntimeSession {
  runtime : @native.Runtime
  definitions : Array[PreparedWindow]
  windows : Array[RunningWindow]
  command_host : CommandHostRuntime?
  pending_bridge : Array[BridgeDispatchTask]
  wakeup : RuntimeWakeup
  forward_menu_events : Bool
  monitor_bridge : Bool
  launch_input_handlers : Array[async (RuntimeLaunchInput) -> Unit noraise]
  window_event_handlers : Array[
    async (WindowHandle, WindowEvent) -> Unit noraise,
  ]
  window_close_handler : (async (WindowHandle) -> WindowCloseDecision noraise)?
  window_tasks : @async.TaskGroup[Unit]
  window_lifecycle_hooks : Array[WindowLifecycleHook]
  lifecycle_failures : Array[AppCleanupError]
  bridge_startup_timeout_ms : Int
  window_commands : Array[WindowSessionCommand]
  pending_window_opens : Array[PendingWindowOpen]
  pending_window_closes : Array[PendingWindowClose]
  pending_browser_requests : Array[PendingBrowserRequest]
  navigation_handler : (async (BrowserHandle, NavigationRequest) -> NavigationDecision noraise)?
  popup_handler : (async (BrowserHandle, PopupRequest) -> PopupDecision noraise)?
  download_handler : (async (BrowserHandle, DownloadRequest) -> DownloadDecision noraise)?
  certificate_handler : (async (BrowserHandle, CertificateError) -> BrowserPermissionDecision noraise)?
  media_handler : (async (BrowserHandle, MediaPermissionRequest) -> BrowserPermissionDecision noraise)?
  download_event_handlers : Array[
    async (BrowserHandle, DownloadEvent) -> Unit noraise,
  ]
}

///|
priv enum WindowSessionCommand {
  Open(String, WindowOpenCompletion)
}

///|
priv struct WindowOpenCompletion {
  mut state : WindowOpenCompletionState
  changed : @async.CondVar
}

///|
priv enum WindowOpenCompletionState {
  WindowOpenPending
  WindowOpenSucceeded(WindowHandle)
  WindowOpenFailed(WindowSessionError)
}

///|
priv struct PendingWindowOpen {
  id : String
  running : RunningWindow
  completion : WindowOpenCompletion
  mut activation : @async.Task[Unit]?
  timeout : @async.Task[Unit]
}

///|
priv struct PendingWindowClose {
  window : Int64
  request_id : Int64
  task : @async.Task[WindowCloseDecision]
}

///|
priv struct PendingBrowserRequest {
  window : Int64
  request_id : Int64
  task : @async.Task[BrowserResponse]
}

///|
priv struct BrowserResponse {
  action : String
  path : String?
}

///|
pub struct BrowserHandle {
  id : String
  native_id : Int64
  load_browser_url : (String) -> Unit raise WindowSessionError
  load_browser_html : (String, String) -> Unit raise WindowSessionError
  eval_browser_script : (String) -> Unit raise WindowSessionError
  send_browser_command : (String, Int?) -> Unit raise WindowSessionError
}

///|
/// A non-owning reference to one concrete web contents view instance.
///
/// Views follow the Electron `WebContentsView` model: each view is an
/// independent web page hosted inside its owning window's content area with
/// explicit top-left bounds, visibility, and z-order. The instance id
/// prevents a stale handle from targeting a later view that reuses the same
/// declarative id.
pub struct ViewHandle {
  id : String
  native_id : Int64
  set_view_bounds : (Int, Int, Int, Int) -> Unit raise WindowSessionError
  set_view_visible : (Bool) -> Unit raise WindowSessionError
  set_view_z_order : (Int) -> Unit raise WindowSessionError
  load_view_url : (String) -> Unit raise WindowSessionError
  read_view_state : () -> @native.ViewState raise WindowSessionError
  close_view : () -> Unit raise WindowSessionError
}

///|
/// A non-owning reference to one concrete window instance.
///
/// The instance id prevents a stale handle from targeting a later window that
/// reuses the same declarative id.
pub struct WindowHandle {
  id : String
  native_id : Int64
  show_window : () -> Unit raise WindowSessionError
  hide_window : () -> Unit raise WindowSessionError
  close_window : () -> Unit raise WindowSessionError
  focus_window : () -> Unit raise WindowSessionError
  set_window_title : (String) -> Unit raise WindowSessionError
  set_window_size : (Int, Int) -> Unit raise WindowSessionError
  minimize_window : () -> Unit raise WindowSessionError
  maximize_window : () -> Unit raise WindowSessionError
  restore_window : () -> Unit raise WindowSessionError
  set_window_fullscreen : (Bool) -> Unit raise WindowSessionError
  set_window_position : (Int, Int) -> Unit raise WindowSessionError
  set_window_always_on_top : (Bool) -> Unit raise WindowSessionError
  set_window_zoom_percent : (Int) -> Unit raise WindowSessionError
  read_window_state : () -> @native.WindowState raise WindowSessionError
  browser : BrowserHandle
  add_view : (String, @native.ViewConfig) -> ViewHandle raise WindowSessionError
  remove_view : (String) -> Unit raise WindowSessionError
  list_views : () -> Array[ViewHandle]
}

///|
/// Opens and locates windows declared by the application manifest.
pub struct WindowManager {
  open_window : async (String) -> WindowHandle raise WindowSessionError
  find_window : (String) -> WindowHandle?
}

///|
/// An observed change to a running native window.
pub(all) enum WindowEvent {
  StateChanged(@native.WindowState)
} derive(Debug, Eq)

///|
/// The result of an asynchronous native close request.
pub(all) enum WindowCloseDecision {
  Allow
  Deny
} derive(Debug, Eq)

///|
pub(all) struct NavigationRequest {
  url : String
  http_method : String
  user_gesture : Bool
  redirect : Bool
} derive(Debug, Eq)

///|
pub(all) enum NavigationDecision {
  Allow
  Deny
} derive(Debug, Eq)

///|
pub(all) struct PopupRequest {
  url : String
  disposition : Int
  user_gesture : Bool
} derive(Debug, Eq)

///|
pub(all) enum PopupDecision {
  Deny
  OpenInCurrent
  OpenInWindow(String)
} derive(Debug, Eq)

///|
pub(all) struct DownloadRequest {
  id : Int
  url : String
  suggested_name : String
} derive(Debug, Eq)

///|
pub(all) enum DownloadDecision {
  Deny
  ShowSaveDialog
  SaveTo(String)
} derive(Debug, Eq)

///|
pub(all) struct CertificateError {
  url : String
  error_code : Int
} derive(Debug, Eq)

///|
pub(all) struct MediaPermissionRequest {
  origin : String
  permissions : Int
} derive(Debug, Eq)

///|
pub(all) enum BrowserPermissionDecision {
  Allow
  Deny
} derive(Debug, Eq)

///|
pub(all) struct DownloadEvent {
  id : Int
  state : String
  received_bytes : Int64
  total_bytes : Int64
  percent : Int
} derive(Debug, Eq)

///|
/// Failures from runtime window lookup, creation, or control.
pub(all) suberror WindowSessionError {
  UnknownWindow(id~ : String)
  AlreadyOpen(id~ : String)
  StaleWindow(id~ : String)
  UnknownView(id~ : String)
  AlreadyExists(id~ : String)
  StaleView(id~ : String)
  Cancelled
  OperationFailed(action~ : String, error~ : @native.NativeError)
  StartupFailed(id~ : String, error~ : AppRunError)
} derive(Debug)

///|
priv enum AppLifecycleState {
  Constructing = 0
  Starting = 1
  Running = 2
  Closing = 3
  Draining = 4
  Destroying = 5
  Closed = 6
}

///|
priv enum BridgeRequestLifecycleState {
  Running = 0
  Responding = 1
  Completed = 2
  Cancelled = 3
  Stale = 4
} derive(Eq)

///|
priv struct AppLifecycle {
  mut state : AppLifecycleState
}

///|
/// Failures while resolving and validating an application's configuration.
pub(all) suberror AppConfigurationError {
  InvalidSetting(name~ : String, message~ : String)
  Bootstrap(@bootstrap.BootstrapError)
  ExtensionDependencyCycle(extension_id~ : String)
  ExtensionUnavailable(
    extension_id~ : String,
    requested_by~ : String?,
    state~ : String
  )
  ExtensionAdaptationFailed(
    extension_id~ : String,
    error~ : @proton_extension.ExtensionAdapterError
  )
  InvalidJavaScriptNamespace(js_namespace~ : String)
  InvalidJavaScriptApi(js_namespace~ : String, api_name~ : String)
  InvalidEntryUrl(url~ : String, reason~ : String)
  InvalidPermissionGrant(detail~ : String)
  MissingPermissionGrant(extension_id~ : String)
} derive(Debug)

///|
/// Failures while loading the application's initial document.
pub(all) suberror AppEntryError {
  ReadFailed(path~ : String, detail~ : String)
  NativeLoad(action~ : String, error~ : @native.NativeError)
  ClosedDuringStartup
} derive(Debug)

///|
/// Failures in the MoonBit-side runtime wakeup source.
pub(all) suberror RuntimeWakeupError {
  UnsupportedFeature(feature~ : String)
  PipeCreateFailed(detail~ : String)
  SourceOpenFailed(source~ : String, detail~ : String)
  SourceClosed
  MissingNotification
} derive(Debug)

///|
/// Failures while starting or stopping command extensions.
pub(all) suberror CommandExtensionLifecycleError {
  ApplicationRegistrationFailed(detail~ : String)
  RegistrationFailed(extension_id~ : String, detail~ : String)
  DestroyFailed(extension_id~ : String, detail~ : String)
} derive(Debug)

///|
/// Failures produced by application or window lifecycle hooks.
pub(all) suberror LifecycleHookError {
  ApplicationStart(index~ : Int, detail~ : String)
  ApplicationShutdown(index~ : Int, detail~ : String)
  WindowReady(index~ : Int, detail~ : String)
  WindowClose(index~ : Int, detail~ : String)
} derive(Debug)

///|
/// A failure from one stage of best-effort application teardown.
pub(all) suberror AppCleanupError {
  CommandExtension(CommandExtensionLifecycleError)
  LifecycleHook(LifecycleHookError)
  WindowDestroy(@native.NativeError)
  RuntimeDestroy(@native.NativeError)
} derive(Debug)

///|
/// Failures produced while configuring, starting, or running an application.
pub(all) suberror AppRunError {
  RunnerError(String)
  ConfigurationError(AppConfigurationError)
  UnsupportedNativeFeature(feature~ : String)
  NativeRuntimeError(action~ : String, error~ : @native.NativeError)
  RuntimeWakeupError(RuntimeWakeupError)
  CommandExtensionLifecycleError(CommandExtensionLifecycleError)
  LifecycleHookError(LifecycleHookError)
  EntryLoadError(AppEntryError)
  BridgeStartupError(@native.BridgeDiagnostic)
  BridgeRuntimeError(@native.BridgeDiagnostic)
  CleanupFailed(primary~ : String?, failures~ : Array[AppCleanupError])
  UnexpectedTaskFailure(detail~ : String)
} derive(Debug)
