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
/// Controls what Proton does after the last application window closes.
pub(all) enum LastWindowClosedPolicy {
  Quit
  KeepRunning
} derive(Eq, Debug)

///|
pub extend LastWindowClosedPolicy with Eq::{not_equal, equal}

///|
pub extend LastWindowClosedPolicy with Debug::{to_repr}

///|
/// Controls when Proton enables the browser accessibility tree.
pub(all) enum AccessibilityMode {
  Automatic
  AlwaysEnabled
} derive(Eq, Debug)

///|
pub extend AccessibilityMode with Eq::{not_equal, equal}

///|
pub extend AccessibilityMode with Debug::{to_repr}

///|
/// High-level application facade for ordinary Proton apps.
struct App {
  mut window : @manifest.WindowManifest
  mut entry : @manifest.AppEntry
  windows : Array[@manifest.AppWindowManifest]
  mut debug_level_value : Int
  mut headless_value : Bool
  mut accessibility_mode_value : AccessibilityMode
  mut application_identity : ApplicationIdentitySource?
  mut single_instance_enabled : Bool
  mut explicit_locale : @locale.Locale?
  path_overrides : Map[String, String]
  mut electron_default_logs_path : Bool
  mut create_logs_path : Bool
  mut bridge_startup_timeout_value_ms : Int
  mut last_window_closed_policy_value : LastWindowClosedPolicy
  mut menu : MenuBar?
  url_schemes : Array[String]
  document_extensions : Array[String]
  mut update_channel : ResolvedUpdateChannel?
  command_capabilities : Array[AppCommandCapability]
  extension_capabilities : Array[ExtensionCapabilityBinding]
  application_lifecycle_hooks : Array[ApplicationLifecycleHook]
  planned_views : Array[(String, ViewConfig)]
  launch_input_handlers : Array[
    async (ApplicationContext, RuntimeLaunchInput) -> Unit noraise,
  ]
  window_event_handlers : Array[
    async (WindowHandle, WindowEvent) -> Unit noraise,
  ]
  view_event_handlers : Array[async (ViewHandle, ViewEvent) -> Unit noraise]
  browser_event_handlers : Array[
    async (BrowserHandle, BrowserEvent) -> Unit noraise,
  ]
  mut window_close_handler : (async (WindowHandle) -> WindowCloseDecision noraise)?
  mut navigation_handler : (async (BrowserHandle, NavigationRequest) -> NavigationDecision noraise)?
  mut new_window_handler : (async (BrowserHandle, NewWindowRequest) -> NewWindowDecision noraise)?
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
priv enum ApplicationIdentitySource {
  ProjectConfig(String)
  Explicit(String)
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
  definition_id : UInt64
  spec : @proton_command.AppCommandExtensionSpec
  event_source : @proton_extension.EventSource?
  scope : Json
  targets : Array[RendererTarget]
}

///|
priv struct RegisteredAppCommandCapability {
  ops : Array[String]
  targets : Array[RendererTarget]
}

///|
priv struct CommandExtensionCatalog {
  specs : Map[String, @proton_command.AppCommandExtensionSpec]
  event_sources : Map[String, @proton_extension.EventSource]
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
let titlebar_area_op = "proton:window/get-titlebar-area"

///|
let titlebar_area_bridge_source =
  #|Object.defineProperty(globalThis.__MoonBit__, "getTitlebarArea", {
  #|  configurable: true,
  #|  enumerable: true,
  #|  value() {
  #|    return globalThis.__MoonBit__.core.invokeOp(
  #|      "proton:window/get-titlebar-area",
  #|      null,
  #|    );
  #|  },
  #|});
  #|

///|
priv struct ResolvedAppConfig {
  manifest : @manifest.AppManifest
  application_name : String
  permission_base_path : String
  application_identifier : String
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
/// Optional command override for `ApplicationContext::relaunch`.
///
/// With neither field set, Proton repeats the current executable and command
/// line. Setting either field switches to Electron's override behavior: the
/// executable still defaults to the current executable, while omitted
/// arguments become an empty array.
pub(all) struct RelaunchOptions {
  executable : String?
  arguments : Array[String]?
} derive(Debug, Eq)

///|
pub extend RelaunchOptions with Eq::{not_equal, equal}

///|
pub extend RelaunchOptions with Debug::{to_repr}

///|
pub fn RelaunchOptions::RelaunchOptions(
  executable? : String,
  arguments? : Array[String],
) -> RelaunchOptions {
  RelaunchOptions::{ executable, arguments, }
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
  mut observed_state : WindowState?
  mut observed_browser_loading : Bool?
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
priv enum CloseCoordinatorState {
  CloseRunning = 0
  CloseQuitRequested = 1
  CloseCollecting = 2
  CloseCommitted = 3
} derive(Eq)

///|
priv struct PendingCloseDecision {
  window : Int64
  task : @async.Task[WindowCloseDecision]
  mut decision : WindowCloseDecision?
  mut native_request : Int64?
}

///|
priv struct CloseCoordinator {
  mut state : CloseCoordinatorState
  pending : Array[PendingCloseDecision]
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
  event_sources : Array[CommandExtensionEventSource]
  mut closed : Bool
}

///|
priv struct CommandExtensionEventSource {
  extension_id : String
  extension_namespace : String
  source : @proton_extension.EventSource
  mut started : Bool
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
  event_pump : RuntimeEventPump
  locale_preferences : @locale.LocalePreferences
  definitions : Array[PreparedWindow]
  windows : Array[RunningWindow]
  mut has_created_window : Bool
  command_host : CommandHostRuntime?
  pending_bridge : Array[BridgeDispatchTask]
  wakeup : RuntimeWakeup
  forward_menu_events : Bool
  monitor_bridge : Bool
  application_tasks : @async.TaskGroup[Unit]
  last_window_closed_policy : LastWindowClosedPolicy
  launch_input_handlers : Array[
    async (ApplicationContext, RuntimeLaunchInput) -> Unit noraise,
  ]
  window_event_handlers : Array[
    async (WindowHandle, WindowEvent) -> Unit noraise,
  ]
  view_event_handlers : Array[async (ViewHandle, ViewEvent) -> Unit noraise]
  browser_event_handlers : Array[
    async (BrowserHandle, BrowserEvent) -> Unit noraise,
  ]
  window_close_handler : (async (WindowHandle) -> WindowCloseDecision noraise)?
  window_tasks : @async.TaskGroup[Unit]
  window_lifecycle_hooks : Array[WindowLifecycleHook]
  lifecycle_failures : Array[AppCleanupError]
  bridge_startup_timeout_ms : Int
  window_commands : Array[WindowSessionCommand]
  pending_window_opens : Array[PendingWindowOpen]
  pending_browser_requests : Array[PendingBrowserRequest]
  pending_resource_requests : Array[PendingResourceRequest]
  navigation_handler : (async (BrowserHandle, NavigationRequest) -> NavigationDecision noraise)?
  new_window_handler : (async (BrowserHandle, NewWindowRequest) -> NewWindowDecision noraise)?
  download_handler : (async (BrowserHandle, DownloadRequest) -> DownloadDecision noraise)?
  certificate_handler : (async (BrowserHandle, CertificateError) -> BrowserPermissionDecision noraise)?
  media_handler : (async (BrowserHandle, MediaPermissionRequest) -> BrowserPermissionDecision noraise)?
  download_event_handlers : Array[
    async (BrowserHandle, DownloadEvent) -> Unit noraise,
  ]
  close_coordinator : CloseCoordinator
  application_identifier : String
  application_executable : String
  application_arguments : Array[String]
  url_schemes : Array[String]
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
/// Sole owner of the native runtime event queue.
///
/// Dialog completions are delivered directly to their waiters. Every other
/// event remains in `session_events` until the runtime session dispatches it.
priv struct RuntimeEventPump {
  runtime : @native.Runtime
  dialog_completions : DialogCompletionStore
  cookie_completions : CookieCompletionStore
  session_events : Array[@native.RuntimeEvent]
}

///|
priv enum CookieCompletionState {
  CookieWaiting
  CookieCompleted(
    Result[Array[@native.NativeCookieRecord], @native.NativeError]
  )
}

///|
priv struct PendingCookieCompletion {
  request_id : Int64
  mut state : CookieCompletionState
  changed : @async.CondVar
}

///|
priv struct CookieCompletionStore {
  pending : Array[PendingCookieCompletion]
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
  focus_browser : () -> Unit raise WindowSessionError
  send_browser_command : (String, Int?) -> Unit raise WindowSessionError
  download_browser_url : (String) -> Unit raise WindowSessionError
  print_browser : () -> Unit raise WindowSessionError
  print_browser_to_pdf : (String, PdfPrintOptions) -> Int raise WindowSessionError
  find_browser_in_page : (String, Bool, Bool, Bool) -> Int raise WindowSessionError
  stop_browser_find : (Bool) -> Unit raise WindowSessionError
  set_browser_zoom_percent : (Int) -> Unit raise WindowSessionError
  read_browser_zoom_percent : () -> Int raise WindowSessionError
  set_browser_audio_muted : (Bool) -> Unit raise WindowSessionError
  read_browser_audio_muted : () -> Bool raise WindowSessionError
  read_browser_navigation_state : () -> (Bool, Bool) raise WindowSessionError
  read_browser_focused : () -> Bool raise WindowSessionError
  read_browser_devtools_opened : () -> Bool raise WindowSessionError
  read_browser_state : () -> BrowserState raise WindowSessionError
  session_handle : SessionHandle
}

///|
/// A non-owning reference to the request context used by one window's main
/// browser, corresponding to Electron's `webContents.session`.
pub struct SessionHandle {
  id : String
  native_id : Int64
  read_cookies : async (String?, Bool) -> Array[Cookie] raise WindowSessionError
  write_cookie : (
    String,
    String,
    String,
    String?,
    String?,
    Bool,
    Bool,
    CookieSameSite,
  ) -> Unit raise WindowSessionError
  remove_cookies : (String?, String?) -> Unit raise WindowSessionError
  flush_cookie_store : () -> Unit raise WindowSessionError
  clear_http_cache : () -> Unit raise WindowSessionError
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
  set_view_zoom_percent : (Int) -> Unit raise WindowSessionError
  read_view_zoom_percent : () -> Int raise WindowSessionError
  set_view_audio_muted : (Bool) -> Unit raise WindowSessionError
  read_view_audio_muted : () -> Bool raise WindowSessionError
  load_view_url : (String) -> Unit raise WindowSessionError
  load_view_html : (String, String) -> Unit raise WindowSessionError
  eval_view_script : (String) -> Unit raise WindowSessionError
  focus_view : () -> Unit raise WindowSessionError
  send_view_command : (String, Int?) -> Unit raise WindowSessionError
  find_view_in_page : (String, Bool, Bool, Bool) -> Int raise WindowSessionError
  stop_view_find : (Bool) -> Unit raise WindowSessionError
  read_view_navigation_state : () -> (Bool, Bool) raise WindowSessionError
  read_view_focused : () -> Bool raise WindowSessionError
  read_view_devtools_opened : () -> Bool raise WindowSessionError
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
  show_window_inactive : () -> Unit raise WindowSessionError
  hide_window : () -> Unit raise WindowSessionError
  close_window : () -> Unit raise WindowSessionError
  focus_window : () -> Unit raise WindowSessionError
  set_window_title : (String) -> Unit raise WindowSessionError
  set_window_icon : (String) -> Unit raise WindowSessionError
  set_window_parent : (WindowHandle?, Bool) -> Unit raise WindowSessionError
  set_window_size : (Int, Int) -> Unit raise WindowSessionError
  set_window_content_size : (Int, Int) -> Unit raise WindowSessionError
  read_window_content_size : () -> (Int, Int) raise WindowSessionError
  minimize_window : () -> Unit raise WindowSessionError
  maximize_window : () -> Unit raise WindowSessionError
  restore_window : () -> Unit raise WindowSessionError
  set_window_fullscreen : (Bool) -> Unit raise WindowSessionError
  set_window_kiosk : (Bool) -> Unit raise WindowSessionError
  set_window_position : (Int, Int) -> Unit raise WindowSessionError
  set_window_always_on_top : (Bool) -> Unit raise WindowSessionError
  set_window_resizable : (Bool) -> Unit raise WindowSessionError
  set_window_minimum_size : (Int, Int) -> Unit raise WindowSessionError
  set_window_maximum_size : (Int, Int) -> Unit raise WindowSessionError
  set_window_aspect_ratio : (Double) -> Unit raise WindowSessionError
  set_window_movable : (Bool) -> Unit raise WindowSessionError
  set_window_opacity : (Double) -> Unit raise WindowSessionError
  set_window_skip_taskbar : (Bool) -> Unit raise WindowSessionError
  set_window_content_protection : (Bool) -> Unit raise WindowSessionError
  set_window_minimizable : (Bool) -> Unit raise WindowSessionError
  set_window_maximizable : (Bool) -> Unit raise WindowSessionError
  set_window_closable : (Bool) -> Unit raise WindowSessionError
  set_window_button_visibility : (Bool) -> Unit raise WindowSessionError
  set_window_focusable : (Bool) -> Unit raise WindowSessionError
  set_window_fullscreenable : (Bool) -> Unit raise WindowSessionError
  set_window_has_shadow : (Bool) -> Unit raise WindowSessionError
  set_window_ignore_mouse_events : (Bool, Bool) -> Unit raise WindowSessionError
  set_window_background_color : (String) -> Unit raise WindowSessionError
  set_window_theme : (WindowThemePreference) -> Unit raise WindowSessionError
  set_window_visible_on_all_workspaces : (Bool) -> Unit raise WindowSessionError
  set_window_enabled : (Bool) -> Unit raise WindowSessionError
  set_window_menu : (MenuBar?) -> Unit raise WindowSessionError
  set_window_zoom_percent : (Int) -> Unit raise WindowSessionError
  set_window_progress_bar : (Double) -> Unit raise WindowSessionError
  flash_window_frame : (Bool) -> Unit raise WindowSessionError
  popup_window_menu : (Menu, Int, Int) -> Unit raise WindowSessionError
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
  Closed
  ReadyToShow
  Moved
  Resized
  Show
  Hide
  Focus
  Blur
  Minimize
  Restore
  Maximize
  Unmaximize
  EnterFullScreen
  LeaveFullScreen
} derive(Debug, Eq)

///|
pub extend WindowEvent with Eq::{not_equal, equal}

///|
pub extend WindowEvent with Debug::{to_repr}

///|
/// Derives Electron-style window transition events from two state snapshots.
/// The full `StateChanged` snapshot is always emitted after transition events.
fn window_state_events(
  previous : WindowState?,
  current : WindowState,
) -> Array[WindowEvent] {
  let events : Array[WindowEvent] = []
  match previous {
    None => if current.visible { events.push(ReadyToShow) }
    Some(previous) => {
      if previous.x != current.x || previous.y != current.y {
        events.push(Moved)
      }
      if previous.width != current.width || previous.height != current.height {
        events.push(Resized)
      }
      if !previous.visible && current.visible {
        events.push(Show)
      } else if previous.visible && !current.visible {
        events.push(Hide)
      }
      if !previous.focused && current.focused {
        events.push(Focus)
      } else if previous.focused && !current.focused {
        events.push(Blur)
      }
      if !previous.minimized && current.minimized {
        events.push(Minimize)
      } else if previous.minimized && !current.minimized {
        events.push(Restore)
      }
      if !previous.maximized && current.maximized {
        events.push(Maximize)
      } else if previous.maximized && !current.maximized {
        events.push(Unmaximize)
      }
      if !previous.fullscreen && current.fullscreen {
        events.push(EnterFullScreen)
      } else if previous.fullscreen && !current.fullscreen {
        events.push(LeaveFullScreen)
      }
    }
  }
  events.push(StateChanged(current))
  events
}

///|
/// An observed change to a running web contents view, following Electron
/// `webContents` lifecycle and page-search events.
pub(all) enum ViewEvent {
  LoadingChanged(is_loading~ : Bool)
  Navigated(url~ : String)
  TitleUpdated(title~ : String)
  LoadFailed(url~ : String, error_code~ : Int, error_text~ : String)
  FoundInPage(result~ : FindInPageResult)
  Closed
} derive(Debug, Eq)

///|
pub extend ViewEvent with Eq::{not_equal, equal}

///|
pub extend ViewEvent with Debug::{to_repr}

///|
/// One update from an active page search. The selection rectangle uses the
/// target web contents coordinate space.
pub(all) struct FindInPageResult {
  request_id : Int
  active_match_ordinal : Int
  matches : Int
  selection_x : Int
  selection_y : Int
  selection_width : Int
  selection_height : Int
  final_update : Bool
} derive(Debug, Eq)

///|
pub extend FindInPageResult with Eq::{not_equal, equal}

///|
pub extend FindInPageResult with Debug::{to_repr}

///|
/// Margins used when printing browser contents to PDF.
pub(all) enum PdfPrintMargins {
  Default
  NoMargins
  Custom(top~ : Double, right~ : Double, bottom~ : Double, left~ : Double)
} derive(Debug, Eq)

///|
pub extend PdfPrintMargins with Eq::{not_equal, equal}

///|
pub extend PdfPrintMargins with Debug::{to_repr}

///|
/// Electron-style PDF print settings. Paper dimensions and custom margins use
/// inches, and scale must be between `0.1` and `2.0`. An empty page range
/// prints the complete document.
pub(all) struct PdfPrintOptions {
  landscape : Bool
  print_background : Bool
  scale : Double
  paper_width : Double
  paper_height : Double
  prefer_css_page_size : Bool
  margins : PdfPrintMargins
  page_ranges : String
  display_header_footer : Bool
  header_template : String
  footer_template : String
  generate_tagged_pdf : Bool
  generate_document_outline : Bool
} derive(Debug, Eq)

///|
pub fn PdfPrintOptions::PdfPrintOptions(
  landscape? : Bool = false,
  print_background? : Bool = false,
  scale? : Double = 1.0,
  paper_width? : Double = 8.5,
  paper_height? : Double = 11.0,
  prefer_css_page_size? : Bool = false,
  margins? : PdfPrintMargins = PdfPrintMargins::Default,
  page_ranges? : String = "",
  display_header_footer? : Bool = false,
  header_template? : String = "",
  footer_template? : String = "",
  generate_tagged_pdf? : Bool = false,
  generate_document_outline? : Bool = false,
) -> PdfPrintOptions {
  {
    landscape,
    print_background,
    scale,
    paper_width,
    paper_height,
    prefer_css_page_size,
    margins,
    page_ranges,
    display_header_footer,
    header_template,
    footer_template,
    generate_tagged_pdf,
    generate_document_outline,
  }
}

///|
pub extend PdfPrintOptions with Eq::{not_equal, equal}

///|
pub extend PdfPrintOptions with Debug::{to_repr}

///|
/// Completion of one `print_to_pdf` request.
pub(all) struct PdfPrintResult {
  request_id : Int
  path : String
  success : Bool
} derive(Debug, Eq)

///|
pub extend PdfPrintResult with Eq::{not_equal, equal}

///|
pub extend PdfPrintResult with Debug::{to_repr}

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
pub(all) struct NewWindowRequest {
  url : String
  user_gesture : Bool
} derive(Debug, Eq)

///|
pub extend NewWindowRequest with Eq::{not_equal, equal}

///|
pub extend NewWindowRequest with Debug::{to_repr}

///|
pub(all) enum NewWindowDecision {
  Deny
  OpenInCurrent
  OpenInWindow(String)
} derive(Debug, Eq)

///|
pub extend NewWindowDecision with Eq::{not_equal, equal}

///|
pub extend NewWindowDecision with Debug::{to_repr}

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
  ApplicationQuitting
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
/// An observed lifecycle change for a window's main browser page.
pub(all) enum BrowserEvent {
  LoadingChanged(is_loading~ : Bool)
  DidStartLoading
  DidFinishLoad
  Navigated(url~ : String)
  TitleUpdated(title~ : String)
  LoadFailed(url~ : String, error_code~ : Int, error_text~ : String)
  FoundInPage(result~ : FindInPageResult)
  PdfPrinted(result~ : PdfPrintResult)
} derive(Debug, Eq)

///|
pub extend BrowserEvent with Eq::{not_equal, equal}

///|
pub extend BrowserEvent with Debug::{to_repr}

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
/// SameSite policy for a browser cookie.
pub(all) enum CookieSameSite {
  Unspecified
  NoRestriction
  Lax
  Strict
} derive(Debug, Eq)

///|
pub extend CookieSameSite with Eq::{not_equal, equal}

///|
pub extend CookieSameSite with Debug::{to_repr}

///|
/// One cookie returned by the browser session.
pub(all) struct Cookie {
  name : String
  value : String
  domain : String
  path : String
  secure : Bool
  http_only : Bool
  same_site : CookieSameSite
  expiration_date : Double?
} derive(Debug, Eq)

///|
pub extend Cookie with Eq::{not_equal, equal}

///|
pub extend Cookie with Debug::{to_repr}

///|

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
/// Failures from application-level desktop and process controls.
pub(all) suberror AppControlError {
  InvalidProtocolScheme(scheme~ : String)
  UndeclaredProtocolScheme(scheme~ : String)
  InvalidExecutable(path~ : String)
  NativeControlFailure(action~ : String, status~ : Int, detail~ : String)
} derive(Debug, Eq)

///|
pub extend AppControlError with Eq::{not_equal, equal}

///|
pub extend AppControlError with Debug::{to_repr}

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
  EventSourceStartFailed(extension_id~ : String, detail~ : String)
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
  LoggingInitializationFailed(detail~ : String)
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
