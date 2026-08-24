///|
/// An operating-system request delivered to an already running application.
pub(all) enum RuntimeLaunchInput {
  OpenUrls(Array[String])
  OpenFiles(Array[String])
  Reopen
} derive(Eq, Debug)

///|
pub extend RuntimeLaunchInput with Eq::{not_equal, equal}

///|
pub extend RuntimeLaunchInput with Debug::{to_repr}

///|
/// High-level application facade for ordinary Proton apps.
struct App {
  mut window : @manifest.WindowManifest
  mut entry : @manifest.AppEntry
  windows : Array[@manifest.AppWindowManifest]
  mut debug_level_value : Int
  mut headless_value : Bool
  mut single_instance_identifier : String?
  mut explicit_locale : @locale.Locale?
  mut bridge_startup_timeout_value_ms : Int
  mut menu : MenuBar?
  url_schemes : Array[String]
  document_extensions : Array[String]
  mut update_channel : ResolvedUpdateChannel?
  command_capabilities : Array[AppCommandCapability]
  extension_capabilities : Array[ExtensionCapabilityBinding]
  application_lifecycle_hooks : Array[ApplicationLifecycleHook]
  planned_views : Array[(String, ViewConfig)]
  launch_input_handlers : Array[async (RuntimeLaunchInput) -> Unit noraise]
  window_event_handlers : Array[
    async (WindowHandle, WindowEvent) -> Unit noraise,
  ]
  view_event_handlers : Array[async (ViewHandle, ViewEvent) -> Unit noraise]
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
/// Identifies one renderer page that may use a capability.
pub struct RendererTarget {
  window : String
  bundled : Bool
}

///|
priv struct AppCommandCapability {
  register : (@proton_command.CommandRegistrar) -> Unit raise
  targets : Array[RendererTarget]
}

///|
priv struct ExtensionCapabilityBinding {
  spec : @proton_command.AppCommandExtensionSpec
  scope : Json
  targets : Array[RendererTarget]
}

///|
priv struct RegisteredAppCommandCapability {
  ops : Array[String]
  targets : Array[RendererTarget]
}

///|
priv struct ResolvedExtensionCapability {
  spec : @proton_command.AppCommandExtensionSpec
  scope : Json
  targets : Array[RendererTarget]
}

///|
priv struct CommandHostBuild {
  runtime : CommandHostRuntime?
  app_capabilities : Array[RegisteredAppCommandCapability]
}

///|
let default_bridge_startup_timeout_ms = 30000

///|
priv struct ResolvedAppConfig {
  manifest : @manifest.AppManifest
  application_name : String
  permission_base_path : String
  application_identifier : String?
  instance_identifier : String?
  url_schemes : Array[String]
  document_extensions : Array[String]
  /// The update channel and the identity it updates, when configured by code.
  update_channel : ResolvedUpdateChannel?
}

///|
priv struct ResolvedUpdateChannel {
  endpoint : String
  public_keys : Array[String]
  check_on_launch : Bool
  freshness_days : Int
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
  mut document : ResourceDocument?
  asset_root : String?
  mut bridge_ready : Bool
  mut state : SessionWindowState
}

///|
priv struct RunningView {
  id : String
  view : @native.View
  mut document : ResourceDocument?
}

///|
priv struct ResourceDocument {
  url : String
  content : Bytes
}

///|
priv enum PreparedEntry {
  RemoteEntry(String)
  DocumentEntry(ResourceDocument, String?)
}

///|
priv struct ResourceResponse {
  status : Int
  mime_type : String
  body : Bytes
}

///|
priv struct PendingResourceRequest {
  request_id : Int64
  window : Int64
  task : @async.Task[ResourceResponse]
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
  entry : PreparedEntry
  bridge : @native.BridgeConfig?
  permissions : WindowPermissionPolicy
  browser_policy : @native.BrowserPolicy
  views : Array[(String, @native.ViewConfig)]
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
  locale_preferences : @locale.LocalePreferences
  definitions : Array[PreparedWindow]
  windows : Array[RunningWindow]
  command_host : CommandHostRuntime?
  pending_bridge : Array[BridgeDispatchTask]
  dialog_completions : DialogCompletionStore
  wakeup : RuntimeWakeup
  forward_menu_events : Bool
  monitor_bridge : Bool
  launch_input_handlers : Array[async (RuntimeLaunchInput) -> Unit noraise]
  window_event_handlers : Array[
    async (WindowHandle, WindowEvent) -> Unit noraise,
  ]
  view_event_handlers : Array[async (ViewHandle, ViewEvent) -> Unit noraise]
  window_close_handler : (async (WindowHandle) -> WindowCloseDecision noraise)?
  window_tasks : @async.TaskGroup[Unit]
  window_lifecycle_hooks : Array[WindowLifecycleHook]
  lifecycle_failures : Array[AppCleanupError]
  bridge_startup_timeout_ms : Int
  window_commands : Array[WindowSessionCommand]
  pending_window_opens : Array[PendingWindowOpen]
  pending_window_closes : Array[PendingWindowClose]
  pending_browser_requests : Array[PendingBrowserRequest]
  pending_resource_requests : Array[PendingResourceRequest]
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
priv enum DialogCompletionState {
  Waiting
  Completed(Result[String, @native.NativeError])
}

///|
priv struct PendingDialogCompletion {
  dialog : Int64
  mut state : DialogCompletionState
  changed : @async.CondVar
}

///|
priv struct DialogCompletionStore {
  pending : Array[PendingDialogCompletion]
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
  load_view_html : (String, String) -> Unit raise WindowSessionError
  eval_view_script : (String) -> Unit raise WindowSessionError
  send_view_command : (String, Int?) -> Unit raise WindowSessionError
  read_view_state : () -> ViewState raise WindowSessionError
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
  read_window_state : () -> WindowState raise WindowSessionError
  browser : BrowserHandle
  add_view : (String, ViewConfig) -> ViewHandle raise WindowSessionError
  remove_view : (String) -> Unit raise WindowSessionError
  list_views : () -> Array[ViewHandle]
  find_view : (String) -> ViewHandle?
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
  StateChanged(WindowState)
} derive(Debug, Eq)

///|
pub extend WindowEvent with Eq::{not_equal, equal}

///|
pub extend WindowEvent with Debug::{to_repr}

///|
/// An observed change to a running web contents view, following the Electron
/// `webContents` lifecycle events.
pub(all) enum ViewEvent {
  LoadingChanged(is_loading~ : Bool)
  Navigated(url~ : String)
  TitleUpdated(title~ : String)
  LoadFailed(url~ : String, error_code~ : Int, error_text~ : String)
} derive(Debug, Eq)

///|
pub extend ViewEvent with Eq::{not_equal, equal}

///|
pub extend ViewEvent with Debug::{to_repr}

///|
/// The result of an asynchronous native close request.
pub(all) enum WindowCloseDecision {
  Allow
  Deny
} derive(Debug, Eq)

///|
pub extend WindowCloseDecision with Eq::{not_equal, equal}

///|
pub extend WindowCloseDecision with Debug::{to_repr}

///|
pub(all) struct NavigationRequest {
  url : String
  http_method : String
  user_gesture : Bool
  redirect : Bool
} derive(Debug, Eq)

///|
pub extend NavigationRequest with Eq::{not_equal, equal}

///|
pub extend NavigationRequest with Debug::{to_repr}

///|
pub(all) enum NavigationDecision {
  Allow
  Deny
} derive(Debug, Eq)

///|
pub extend NavigationDecision with Eq::{not_equal, equal}

///|
pub extend NavigationDecision with Debug::{to_repr}

///|
pub(all) struct PopupRequest {
  url : String
  disposition : Int
  user_gesture : Bool
} derive(Debug, Eq)

///|
pub extend PopupRequest with Eq::{not_equal, equal}

///|
pub extend PopupRequest with Debug::{to_repr}

///|
pub(all) enum PopupDecision {
  Deny
  OpenInCurrent
  OpenInWindow(String)
} derive(Debug, Eq)

///|
pub extend PopupDecision with Eq::{not_equal, equal}

///|
pub extend PopupDecision with Debug::{to_repr}

///|
pub(all) struct DownloadRequest {
  id : Int
  url : String
  suggested_name : String
} derive(Debug, Eq)

///|
pub extend DownloadRequest with Eq::{not_equal, equal}

///|
pub extend DownloadRequest with Debug::{to_repr}

///|
pub(all) enum DownloadDecision {
  Deny
  ShowSaveDialog
  SaveTo(String)
} derive(Debug, Eq)

///|
pub extend DownloadDecision with Eq::{not_equal, equal}

///|
pub extend DownloadDecision with Debug::{to_repr}

///|
pub(all) struct CertificateError {
  url : String
  error_code : Int
} derive(Debug, Eq)

///|
pub extend CertificateError with Eq::{not_equal, equal}

///|
pub extend CertificateError with Debug::{to_repr}

///|
pub(all) struct MediaPermissionRequest {
  origin : String
  permissions : Int
} derive(Debug, Eq)

///|
pub extend MediaPermissionRequest with Eq::{not_equal, equal}

///|
pub extend MediaPermissionRequest with Debug::{to_repr}

///|
pub(all) enum BrowserPermissionDecision {
  Allow
  Deny
} derive(Debug, Eq)

///|
pub extend BrowserPermissionDecision with Eq::{not_equal, equal}

///|
pub extend BrowserPermissionDecision with Debug::{to_repr}

///|
pub(all) struct DownloadEvent {
  id : Int
  state : String
  received_bytes : Int64
  total_bytes : Int64
  percent : Int
} derive(Debug, Eq)

///|
pub extend DownloadEvent with Eq::{not_equal, equal}

///|
pub extend DownloadEvent with Debug::{to_repr}

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
  OperationFailed(action~ : String, status~ : Int, detail~ : String)
  StartupFailed(id~ : String, error~ : AppRunError)
} derive(Debug)

///|
pub extend WindowSessionError with Debug::{to_repr}

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
  InvalidRendererCapability(detail~ : String)
} derive(Debug)

///|
pub extend AppConfigurationError with Debug::{to_repr}

///|
/// Failures while loading the application's initial document.
pub(all) suberror AppEntryError {
  ReadFailed(path~ : String, detail~ : String)
  PlatformLoad(action~ : String, status~ : Int, detail~ : String)
  ClosedDuringStartup
} derive(Debug)

///|
pub extend AppEntryError with Debug::{to_repr}

///|
/// Failures while starting or stopping command extensions.
pub(all) suberror CommandExtensionLifecycleError {
  ApplicationRegistrationFailed(detail~ : String)
  RegistrationFailed(extension_id~ : String, detail~ : String)
  DestroyFailed(extension_id~ : String, detail~ : String)
} derive(Debug)

///|
pub extend CommandExtensionLifecycleError with Debug::{to_repr}

///|
/// Failures produced by application or window lifecycle hooks.
pub(all) suberror LifecycleHookError {
  ApplicationStart(index~ : Int, detail~ : String)
  ApplicationShutdown(index~ : Int, detail~ : String)
  WindowReady(index~ : Int, detail~ : String)
  WindowClose(index~ : Int, detail~ : String)
} derive(Debug)

///|
pub extend LifecycleHookError with Debug::{to_repr}

///|
/// A failure from one stage of best-effort application teardown.
pub(all) suberror AppCleanupError {
  CommandExtension(CommandExtensionLifecycleError)
  LifecycleHook(LifecycleHookError)
  WindowDestroy(status~ : Int, detail~ : String)
  RuntimeDestroy(status~ : Int, detail~ : String)
} derive(Debug)

///|
pub extend AppCleanupError with Debug::{to_repr}

///|
/// Failures produced while configuring, starting, or running an application.
pub(all) suberror AppRunError {
  EventLoopError(String)
  ConfigurationError(AppConfigurationError)
  UnsupportedNativeFeature(feature~ : String)
  RuntimeOperationFailed(action~ : String, status~ : Int, detail~ : String)
  CommandExtensionLifecycleError(CommandExtensionLifecycleError)
  LifecycleHookError(LifecycleHookError)
  EntryLoadError(AppEntryError)
  BridgeStartupError(BridgeDiagnostic)
  BridgeRuntimeError(BridgeDiagnostic)
  CleanupFailed(primary~ : String?, failures~ : Array[AppCleanupError])
  UnexpectedTaskFailure(detail~ : String)
} derive(Debug)

///|
pub extend AppRunError with Debug::{to_repr}
