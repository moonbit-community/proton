///|
/// Failures at Proton's private MoonBit/native boundary.
pub(all) suberror NativeError {
  /// A negative status returned by a private platform stub.
  Status(status~ : Int, message~ : String)
  /// An invalid argument rejected before entering the C ABI.
  InvalidArgument(message~ : String)
  /// Malformed data returned by the native runtime.
  InvalidPayload(context~ : String, message~ : String)
} derive(Debug, Eq)

///|
pub extend NativeError with Eq::{not_equal, equal}

///|
pub extend NativeError with Debug::{to_repr}

///|
pub extend NativeError with Show::{to_string, output}

///|
pub fn NativeError::status(self : NativeError) -> Int {
  match self {
    Status(status~, ..) => status
    InvalidArgument(..) | InvalidPayload(..) => -1
  }
}

///|
pub fn NativeError::message(self : NativeError) -> String {
  match self {
    Status(message~, ..) | InvalidArgument(message~) => message
    InvalidPayload(context~, message~) =>
      "failed to decode " + context + ": " + message
  }
}

///|
/// Reports whether the native object is closing or has already been destroyed.
pub fn NativeError::is_invalid_state(self : NativeError) -> Bool {
  self.status() == proton_err_invalid_state
}

///|
/// Reports whether a bridge response lost its renderer request while an
/// asynchronous handler was still completing.
pub fn NativeError::is_stale_bridge_response(self : NativeError) -> Bool {
  self.status() == proton_err_stale_bridge_response
}

///|
pub fn NativeError::is_stale_window_request(self : NativeError) -> Bool {
  self.status() == proton_err_stale_window_request
}

///|
pub fn NativeError::is_stale_browser_request(self : NativeError) -> Bool {
  self.status() == proton_err_stale_browser_request
}

///|
pub fn NativeError::is_stale_resource_request(self : NativeError) -> Bool {
  self.status() == proton_err_stale_resource_request
}

///|
pub fn NativeError::is_update_busy(self : NativeError) -> Bool {
  self.status() == proton_err_update_busy
}

///|
pub fn NativeError::is_update_rollback(self : NativeError) -> Bool {
  self.status() == proton_err_update_rollback
}

///|
pub fn NativeError::is_update_revision_mismatch(self : NativeError) -> Bool {
  self.status() == proton_err_update_revision_mismatch
}

///|
impl Show for NativeError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub(all) enum ProcessResult {
  MainProcess
  SubprocessHandled(Int)
} derive(Debug, Eq)

///|
pub extend ProcessResult with Eq::{not_equal, equal}

///|
pub extend ProcessResult with Debug::{to_repr}

///|
pub(all) struct RuntimeInfo {
  platform : String
  /// The source-built target identifier, such as `darwin-arm64`. Matches the
  /// platform keys in an update manifest.
  platform_id : String
  features : Array[String]
} derive(Debug, Eq)

///|
pub extend RuntimeInfo with Eq::{not_equal, equal}

///|
pub extend RuntimeInfo with Debug::{to_repr}

///|
pub(all) enum SystemPathKind {
  Desktop
  Documents
  Downloads
  Music
  Pictures
  Videos
  Recent
} derive(Debug, Eq)

///|
pub extend SystemPathKind with Eq::{not_equal, equal}

///|
pub extend SystemPathKind with Debug::{to_repr}

///|
pub(all) struct RuntimeWaitReady {
  mask : Int
} derive(Debug, Eq)

///|
pub extend RuntimeWaitReady with Eq::{not_equal, equal}

///|
pub extend RuntimeWaitReady with Debug::{to_repr}

///|
pub(all) enum AccessibilityMode {
  Automatic = 0
  AlwaysEnabled = 1
} derive(Debug, Eq)

///|
pub extend AccessibilityMode with Eq::{not_equal, equal}

///|
pub extend AccessibilityMode with Debug::{to_repr}

///|
/// Inputs forwarded by a second operating-system application instance.
pub(all) struct AppActivation {
  abi_version : Int
  urls : Array[String]
  files : Array[String]
  reopen : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AppActivation with Eq::{not_equal, equal}

///|
pub extend AppActivation with Debug::{to_repr}

///|
pub extend AppActivation with ToJson::{to_json}

///|
pub extend AppActivation with FromJson::{from_json}

///|
/// Result of claiming an operating-system application identity.
pub enum AppInstanceAcquire {
  Primary(AppInstance)
  Forwarded
}

///|
struct AppInstance {
  mut handle : Int64
  mut destroyed : Bool
}

///|
enum RuntimeEvent {
  WindowCreated(Int64)
  WindowClosed(Int64)
  WindowStateChanged(Int64, WindowState)
  WindowCloseRequested(Int64, Int64)
  BridgeLifecycleChanged(Int64, Int64)
  BridgeRequestReceived(BridgeRequest)
  BridgeRequestCancelled(Int64)
  DialogCompleted(NativeDialogCompletion)
  CookieGetCompleted(NativeCookieGetCompletion)
  MenuCommand(String, Int64?)
  LaunchInput(RuntimeLaunchInput)
  AppActivationReceived(AppActivation)
  NotificationResult(NativeNotificationResult)
  NotificationClicked(String?)
  BrowserRequest(Int64, NativeBrowserRequest)
  BrowserDownloadUpdated(Int64, NativeDownloadUpdate)
  BrowserPdfPrinted(Int64, NativePdfPrintResult)
  BrowserEvent(Int64, NativeBrowserEvent)
  ViewEvent(Int64, Int64, NativeViewEvent)
  ResourceRequested(NativeResourceRequest)
  ResourceRequestCancelled(Int64)
  QuitRequested
} derive(Debug, Eq)

///|
pub(all) struct NativeResourceRequest {
  request_id : Int64
  window : Int64
  view : Int64?
  url : String
} derive(Debug, Eq)

///|
pub extend NativeResourceRequest with Eq::{not_equal, equal}

///|
pub extend NativeResourceRequest with Debug::{to_repr}

///|
pub(all) struct NativeFindInPageResult {
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
pub extend NativeFindInPageResult with Eq::{not_equal, equal}

///|
pub extend NativeFindInPageResult with Debug::{to_repr}

///|
pub(all) struct PdfPrintSettings {
  landscape : Bool
  print_background : Bool
  scale : Double
  paper_width : Double
  paper_height : Double
  prefer_css_page_size : Bool
  margin_type : Int
  margin_top : Double
  margin_right : Double
  margin_bottom : Double
  margin_left : Double
  page_ranges : String
  display_header_footer : Bool
  header_template : String
  footer_template : String
  generate_tagged_pdf : Bool
  generate_document_outline : Bool
} derive(Debug, Eq)

///|
pub extend PdfPrintSettings with Eq::{not_equal, equal}

///|
pub extend PdfPrintSettings with Debug::{to_repr}

///|
enum NativeViewEvent {
  LoadingChanged(Bool)
  Navigated(String)
  TitleUpdated(String)
  LoadFailed(String, Int, String)
  FindResult(NativeFindInPageResult)
  Closed
} derive(Debug, Eq)

///|
pub extend NativeViewEvent with Eq::{not_equal, equal}

///|
pub extend NativeViewEvent with Debug::{to_repr}

///|
pub extend RuntimeEvent with Eq::{not_equal, equal}

///|
pub extend RuntimeEvent with Debug::{to_repr}

///|
/// A macOS application activation delivered by Launch Services or the Dock.
pub(all) enum RuntimeLaunchInput {
  OpenUrls(Array[String])
  OpenFiles(Array[String])
  Reopen
} derive(Debug, Eq)

///|
pub extend RuntimeLaunchInput with Eq::{not_equal, equal}

///|
pub extend RuntimeLaunchInput with Debug::{to_repr}

///|
pub(all) enum NativeNotificationResult {
  Delivered
  Failed(String)
} derive(Debug, Eq)

///|
pub extend NativeNotificationResult with Eq::{not_equal, equal}

///|
pub extend NativeNotificationResult with Debug::{to_repr}

///|
pub(all) enum NativeBrowserRequest {
  Navigation(
    request_id~ : Int64,
    url~ : String,
    http_method~ : String,
    user_gesture~ : Bool,
    redirect~ : Bool
  )
  NewWindow(request_id~ : Int64, url~ : String, user_gesture~ : Bool)
  Download(
    request_id~ : Int64,
    download_id~ : Int,
    url~ : String,
    suggested_name~ : String
  )
  Certificate(request_id~ : Int64, url~ : String, error_code~ : Int)
  Media(request_id~ : Int64, origin~ : String, permissions~ : Int)
} derive(Debug, Eq)

///|
pub extend NativeBrowserRequest with Eq::{not_equal, equal}

///|
pub extend NativeBrowserRequest with Debug::{to_repr}

///|
pub(all) struct NativeDownloadUpdate {
  download_id : Int
  state : String
  received_bytes : Int64
  total_bytes : Int64
  percent : Int
} derive(Debug, Eq)

///|
pub extend NativeDownloadUpdate with Eq::{not_equal, equal}

///|
pub extend NativeDownloadUpdate with Debug::{to_repr}

///|
pub(all) struct NativePdfPrintResult {
  request_id : Int
  path : String
  success : Bool
} derive(Debug, Eq)

///|
pub extend NativePdfPrintResult with Eq::{not_equal, equal}

///|
pub extend NativePdfPrintResult with Debug::{to_repr}

///|
pub(all) struct BridgeLifecycleState {
  revision : String
  outcome : String
  page_instance : String
  url : String
  failure_pending : Bool
} derive(Debug, Eq)

///|
pub extend BridgeLifecycleState with Eq::{not_equal, equal}

///|
pub extend BridgeLifecycleState with Debug::{to_repr}

///|
pub(all) struct BridgeDiagnostic {
  stage : String
  code : String
  message : String
  page_instance : String
  url : String
  owner : String?
  source_url : String?
  source_line : String?
  line : Int?
  column : Int?
  stack : String?
  additional_failure_count : Int?
  details_truncated : Bool
} derive(Debug, Eq)

///|
pub extend BridgeDiagnostic with Eq::{not_equal, equal}

///|
pub extend BridgeDiagnostic with Debug::{to_repr}

///|
pub(all) struct BridgeRequest {
  request_id : Int64
  window : Int64
  op : String
  payload : Json
  page_instance : String?
  source_origin : String
} derive(Debug, Eq)

///|
pub extend BridgeRequest with Debug::{to_repr}

///|
pub extend BridgeRequest with Eq::{not_equal, equal}

///|
pub(all) enum BridgeResponse {
  Ok(request_id~ : Int64, payload~ : Json)
  Err(request_id~ : Int64, code~ : String, message~ : String)
} derive(Debug)

///|
pub extend BridgeResponse with Debug::{to_repr}

///|
pub(all) enum DialogLevel {
  Info = 0
  Warning = 1
  Error = 2
} derive(Debug, Eq)

///|
pub extend DialogLevel with Eq::{not_equal, equal}

///|
pub extend DialogLevel with Debug::{to_repr}

///|
fn DialogLevel::native_value(self : DialogLevel) -> Int {
  match self {
    Info => 0
    Warning => 1
    Error => 2
  }
}

///|
enum NativeBrowserEvent {
  LoadingChanged(Bool)
  Navigated(String)
  TitleUpdated(String)
  LoadFailed(String, Int, String)
  FindResult(NativeFindInPageResult)
} derive(Debug, Eq)

///|
pub extend NativeBrowserEvent with Eq::{not_equal, equal}

///|
pub extend NativeBrowserEvent with Debug::{to_repr}

///|
pub(all) struct NativeDialogCompletion {
  dialog : Int64
  window : Int64?
  result : Result[String, NativeError]
} derive(Debug, Eq)

///|
pub extend NativeDialogCompletion with Eq::{not_equal, equal}

///|
pub extend NativeDialogCompletion with Debug::{to_repr}

///|
pub(all) struct NativeCookieGetCompletion {
  request_id : Int64
  window : Int64
  result : Result[Array[NativeCookieRecord], NativeError]
} derive(Debug, Eq)

///|
pub extend NativeCookieGetCompletion with Eq::{not_equal, equal}

///|
pub extend NativeCookieGetCompletion with Debug::{to_repr}

///|
pub(all) struct NativeCookieRecord {
  name : String
  value : String
  domain : String
  path : String
  secure : Bool
  http_only : Bool
  same_site : CookieSameSite
  expires : Int64?
} derive(Debug, Eq)

///|
pub extend NativeCookieRecord with Eq::{not_equal, equal}

///|
pub extend NativeCookieRecord with Debug::{to_repr}

///|
pub(all) enum CookieSameSite {
  Unspecified = 0
  NoRestriction = 1
  Lax = 2
  Strict = 3
} derive(Debug, Eq)

///|
pub extend CookieSameSite with Eq::{not_equal, equal}

///|
pub extend CookieSameSite with Debug::{to_repr}

///|
fn CookieSameSite::native_value(self : CookieSameSite) -> Int {
  match self {
    Unspecified => 0
    NoRestriction => 1
    Lax => 2
    Strict => 3
  }
}

///|
/// Geometry and scaling information for the monitor containing a window.
pub(all) struct WindowMonitor {
  x : Int
  y : Int
  width : Int
  height : Int
  work_x : Int
  work_y : Int
  work_width : Int
  work_height : Int
  scale_factor_percent : Int
} derive(Debug, Eq)

///|
pub extend WindowMonitor with Eq::{not_equal, equal}

///|
pub extend WindowMonitor with Debug::{to_repr}

///|
/// A point-in-time native window state snapshot.
///
/// `theme` is the effective theme after resolving `theme_preference`.
pub(all) struct WindowState {
  x : Int
  y : Int
  width : Int
  height : Int
  monitor : WindowMonitor
  zoom_percent : Int
  visible : Bool
  focused : Bool
  minimized : Bool
  maximized : Bool
  fullscreen : Bool
  always_on_top : Bool
  theme : WindowTheme
} derive(Debug, Eq)

///|
/// A point-in-time state snapshot for a window's main browser page.
pub(all) struct BrowserState {
  url : String
  title : String
  is_loading : Bool
  can_go_back : Bool
  can_go_forward : Bool
} derive(Debug, Eq)

///|
pub extend BrowserState with Eq::{not_equal, equal}

///|
pub extend BrowserState with Debug::{to_repr}

///|
/// Information about a single connected display.
pub(all) struct ScreenInfo {
  id : Int
  x : Int
  y : Int
  width : Int
  height : Int
  work_x : Int
  work_y : Int
  work_width : Int
  work_height : Int
  scale_factor_percent : Int
  is_primary : Bool
} derive(Debug, Eq)

///|
pub extend ScreenInfo with Eq::{not_equal, equal}

///|
pub extend ScreenInfo with Debug::{to_repr}

///|
pub extend WindowState with Eq::{not_equal, equal}

///|
pub extend WindowState with Debug::{to_repr}

///|
/// An application-level native menu bar.
struct MenuBar {
  menus : Array[Menu]
} derive(Debug, Eq)

///|
pub extend MenuBar with Eq::{not_equal, equal}

///|
pub extend MenuBar with Debug::{to_repr}

///|
/// A top-level native menu and its items.
struct Menu {
  label : String?
  role : MenuRole?
  items : Array[MenuItem]?
} derive(Debug, Eq)

///|
pub extend Menu with Eq::{not_equal, equal}

///|
pub extend Menu with Debug::{to_repr}

///|
/// A command, separator, or platform role in a native menu.
struct MenuItem {
  kind : MenuItemKind
  id : String?
  label : String?
  key : String?
  role : MenuItemRole?
  submenu : Menu?
  enabled : Bool
  visible : Bool
  checked : Bool?
} derive(Debug, Eq)

///|
priv enum MenuItemKind {
  Command
  Separator
  Role
  Submenu
} derive(Debug, Eq)

///|
pub extend MenuItem with Eq::{not_equal, equal}

///|
pub extend MenuItem with Debug::{to_repr}

///|
/// A standard top-level application menu role.
pub(all) enum MenuRole {
  Application
  File
  Edit
  View
  Window
  Help
} derive(Debug, Eq)

///|
pub extend MenuRole with Eq::{not_equal, equal}

///|
pub extend MenuRole with Debug::{to_repr}

///|
/// A standard native menu action.
pub(all) enum MenuItemRole {
  Quit
  Hide
  HideOthers
  ShowAll
  Close
  Minimize
  Zoom
  Undo
  Redo
  Cut
  Copy
  Paste
  SelectAll
} derive(Debug, Eq)

///|
pub extend MenuItemRole with Eq::{not_equal, equal}

///|
pub extend MenuItemRole with Debug::{to_repr}

///|
pub(all) struct BridgeConfig {
  max_payload_bytes : Int
  grants : Array[BridgeGrantConfig]
} derive(Debug, Eq)

///|
pub extend BridgeConfig with Eq::{not_equal, equal}

///|
pub extend BridgeConfig with Debug::{to_repr}

///|
/// Renderer capabilities granted to one canonical source in one window.
pub(all) struct BridgeGrantConfig {
  source_origin : String
  ops : Array[String]
  extensions : Array[BridgeExtensionConfig]
  initialization_units : Array[BridgeInitializationUnit]
} derive(Debug, Eq)

///|
pub extend BridgeGrantConfig with Eq::{not_equal, equal}

///|
pub extend BridgeGrantConfig with Debug::{to_repr}

///|
/// One JavaScript namespace installed by the renderer bootstrap.
pub(all) struct BridgeExtensionConfig {
  js_namespace : String
  apis : Array[String]
} derive(Debug, Eq)

///|
pub extend BridgeExtensionConfig with Eq::{not_equal, equal}

///|
pub extend BridgeExtensionConfig with Debug::{to_repr}

///|
/// One ordered JavaScript initialization unit owned by an extension.
pub(all) struct BridgeInitializationUnit {
  owner : String
  name : String
  source : String
} derive(Debug, Eq)

///|
pub extend BridgeInitializationUnit with Eq::{not_equal, equal}

///|
pub extend BridgeInitializationUnit with Debug::{to_repr}

///|
pub fn RuntimeEvent::event_type(self : RuntimeEvent) -> String {
  match self {
    WindowCreated(_) => "window_created"
    WindowClosed(_) => "window_closed"
    WindowStateChanged(_, _) => "window_state_changed"
    WindowCloseRequested(_, _) => "window_close_requested"
    BridgeLifecycleChanged(_, _) => "bridge_lifecycle_changed"
    BridgeRequestReceived(_) => "bridge_request_received"
    BridgeRequestCancelled(_) => "bridge_request_cancelled"
    DialogCompleted(_) => "dialog_completed"
    CookieGetCompleted(_) => "cookie_get_completed"
    MenuCommand(_, _) => "menu_command"
    LaunchInput(OpenUrls(_)) => "open_urls"
    LaunchInput(OpenFiles(_)) => "open_files"
    LaunchInput(Reopen) => "reopen"
    AppActivationReceived(_) => "app_activation"
    NotificationResult(_) => "notification_result"
    NotificationClicked(_) => "notification_clicked"
    BrowserRequest(_, Navigation(..)) => "browser_navigation_requested"
    BrowserRequest(_, NewWindow(..)) => "browser_new_window_requested"
    BrowserRequest(_, Download(..)) => "browser_download_requested"
    BrowserRequest(_, Certificate(..)) => "browser_certificate_error"
    BrowserRequest(_, Media(..)) => "browser_media_permission_requested"
    BrowserDownloadUpdated(_, _) => "browser_download_updated"
    BrowserPdfPrinted(_, _) => "browser_pdf_print_finished"
    BrowserEvent(_, LoadingChanged(_)) => "browser_loading_changed"
    BrowserEvent(_, Navigated(_)) => "browser_navigated"
    BrowserEvent(_, TitleUpdated(_)) => "browser_title_updated"
    BrowserEvent(_, LoadFailed(_, _, _)) => "browser_load_failed"
    BrowserEvent(_, FindResult(_)) => "browser_found_in_page"
    ViewEvent(_, _, LoadingChanged(_)) => "view_loading_changed"
    ViewEvent(_, _, Navigated(_)) => "view_navigated"
    ViewEvent(_, _, TitleUpdated(_)) => "view_title_updated"
    ViewEvent(_, _, LoadFailed(_, _, _)) => "view_load_failed"
    ViewEvent(_, _, FindResult(_)) => "view_found_in_page"
    ViewEvent(_, _, Closed) => "view_closed"
    ResourceRequested(_) => "resource_requested"
    ResourceRequestCancelled(_) => "resource_request_cancelled"
    QuitRequested => "quit_requested"
  }
}

///|
pub fn RuntimeEvent::has_window(self : RuntimeEvent) -> Bool {
  self.window_id() is Some(_)
}

///|
/// Returns the window associated with this event when one exists. For an app
/// menu command this is the focused window at click time.
pub fn RuntimeEvent::window_id(self : RuntimeEvent) -> Int64? {
  match self {
    WindowCreated(window)
    | WindowClosed(window)
    | WindowStateChanged(window, _)
    | WindowCloseRequested(window, _)
    | BridgeLifecycleChanged(window, _)
    | BrowserRequest(window, _)
    | BrowserDownloadUpdated(window, _)
    | BrowserPdfPrinted(window, _)
    | BrowserEvent(window, _)
    | ViewEvent(window, _, _) => Some(window)
    ResourceRequested(request) => Some(request.window)
    MenuCommand(_, window) => window
    DialogCompleted(completion) => completion.window
    CookieGetCompleted(completion) => Some(completion.window)
    BridgeRequestReceived(_)
    | BridgeRequestCancelled(_)
    | ResourceRequestCancelled(_)
    | LaunchInput(_)
    | AppActivationReceived(_)
    | NotificationResult(_)
    | NotificationClicked(_)
    | QuitRequested => None
  }
}

///|
/// Returns the web contents view associated with this event when one exists.
pub fn RuntimeEvent::view_id(self : RuntimeEvent) -> Int64? {
  match self {
    ViewEvent(_, view, _) => Some(view)
    ResourceRequested(request) => request.view
    _ => None
  }
}

///|
pub fn RuntimeEvent::resource_request(
  self : RuntimeEvent,
) -> NativeResourceRequest? {
  match self {
    ResourceRequested(request) => Some(request)
    _ => None
  }
}

///|
pub fn RuntimeEvent::resource_request_cancellation(
  self : RuntimeEvent,
) -> Int64? {
  match self {
    ResourceRequestCancelled(request_id) => Some(request_id)
    _ => None
  }
}

///|
/// The payload of a web contents view lifecycle event.
pub(all) struct ViewEventInfo {
  url : String?
  title : String?
  is_loading : Bool?
  error_code : Int?
  error_text : String?
} derive(Debug, Eq)

///|
pub extend ViewEventInfo with Eq::{not_equal, equal}

///|
pub extend ViewEventInfo with Debug::{to_repr}

///|
/// Returns the view event payload when this event carries one.
pub fn RuntimeEvent::view_event(self : RuntimeEvent) -> ViewEventInfo? {
  match self {
    ViewEvent(_, _, LoadingChanged(is_loading)) =>
      Some({
        url: None,
        title: None,
        is_loading: Some(is_loading),
        error_code: None,
        error_text: None,
      })
    ViewEvent(_, _, Navigated(url)) =>
      Some({
        url: Some(url),
        title: None,
        is_loading: None,
        error_code: None,
        error_text: None,
      })
    ViewEvent(_, _, TitleUpdated(title)) =>
      Some({
        url: None,
        title: Some(title),
        is_loading: None,
        error_code: None,
        error_text: None,
      })
    ViewEvent(_, _, LoadFailed(url, error_code, error_text)) =>
      Some({
        url: Some(url),
        title: None,
        is_loading: None,
        error_code: Some(error_code),
        error_text: Some(error_text),
      })
    ViewEvent(_, _, Closed) =>
      Some({
        url: None,
        title: None,
        is_loading: None,
        error_code: None,
        error_text: None,
      })
    _ => None
  }
}

///|
/// Returns the main browser event payload when this event carries one.
pub fn RuntimeEvent::browser_event(self : RuntimeEvent) -> ViewEventInfo? {
  match self {
    BrowserEvent(_, LoadingChanged(is_loading)) =>
      Some({
        url: None,
        title: None,
        is_loading: Some(is_loading),
        error_code: None,
        error_text: None,
      })
    BrowserEvent(_, Navigated(url)) =>
      Some({
        url: Some(url),
        title: None,
        is_loading: None,
        error_code: None,
        error_text: None,
      })
    BrowserEvent(_, TitleUpdated(title)) =>
      Some({
        url: None,
        title: Some(title),
        is_loading: None,
        error_code: None,
        error_text: None,
      })
    BrowserEvent(_, LoadFailed(url, error_code, error_text)) =>
      Some({
        url: Some(url),
        title: None,
        is_loading: None,
        error_code: Some(error_code),
        error_text: Some(error_text),
      })
    _ => None
  }
}

///|
pub fn RuntimeEvent::find_in_page_result(
  self : RuntimeEvent,
) -> NativeFindInPageResult? {
  match self {
    BrowserEvent(_, FindResult(result)) | ViewEvent(_, _, FindResult(result)) =>
      Some(result)
    _ => None
  }
}

///|
pub fn RuntimeEvent::is_view_closed(self : RuntimeEvent) -> Bool {
  self is ViewEvent(_, _, Closed)
}

///|
pub fn RuntimeEvent::is_window_created(self : RuntimeEvent) -> Bool {
  self is WindowCreated(_)
}

///|
pub fn RuntimeEvent::is_window_closed(self : RuntimeEvent) -> Bool {
  self is WindowClosed(_)
}

///|
pub fn RuntimeEvent::is_quit_requested(self : RuntimeEvent) -> Bool {
  self is QuitRequested
}

///|
pub fn RuntimeEvent::window_state_change(self : RuntimeEvent) -> WindowState? {
  match self {
    WindowStateChanged(_, state) => Some(state)
    _ => None
  }
}

///|
pub fn RuntimeEvent::window_close_request(self : RuntimeEvent) -> Int64? {
  match self {
    WindowCloseRequested(_, request_id) => Some(request_id)
    _ => None
  }
}

///|
pub fn RuntimeEvent::browser_request(
  self : RuntimeEvent,
) -> NativeBrowserRequest? {
  match self {
    BrowserRequest(_, request) => Some(request)
    _ => None
  }
}

///|
pub fn RuntimeEvent::browser_download_update(
  self : RuntimeEvent,
) -> NativeDownloadUpdate? {
  match self {
    BrowserDownloadUpdated(_, update) => Some(update)
    _ => None
  }
}

///|
pub fn RuntimeEvent::pdf_print_result(
  self : RuntimeEvent,
) -> NativePdfPrintResult? {
  match self {
    BrowserPdfPrinted(_, result) => Some(result)
    _ => None
  }
}

///|
pub fn RuntimeEvent::is_bridge_lifecycle_changed(self : RuntimeEvent) -> Bool {
  self is BridgeLifecycleChanged(_, _)
}

///|
pub fn RuntimeEvent::bridge_request_cancellation(self : RuntimeEvent) -> Int64? {
  match self {
    BridgeRequestCancelled(request_id) => Some(request_id)
    _ => None
  }
}

///|
pub fn RuntimeEvent::bridge_request(self : RuntimeEvent) -> BridgeRequest? {
  match self {
    BridgeRequestReceived(request) => Some(request)
    _ => None
  }
}

///|
pub fn RuntimeEvent::dialog_completion(
  self : RuntimeEvent,
) -> NativeDialogCompletion? {
  match self {
    DialogCompleted(completion) => Some(completion)
    _ => None
  }
}

///|
pub fn RuntimeEvent::cookie_get_completion(
  self : RuntimeEvent,
) -> NativeCookieGetCompletion? {
  match self {
    CookieGetCompleted(completion) => Some(completion)
    _ => None
  }
}

///|
/// The command id for an app-menu command item click, or `None` for every
/// other event kind.
pub fn RuntimeEvent::menu_command_id(self : RuntimeEvent) -> String? {
  match self {
    MenuCommand(command_id, _) => Some(command_id)
    _ => None
  }
}

///|
/// Returns the typed application launch input carried by this event.
pub fn RuntimeEvent::launch_input(self : RuntimeEvent) -> RuntimeLaunchInput? {
  match self {
    LaunchInput(input) => Some(input)
    _ => None
  }
}

///|
pub fn RuntimeEvent::app_activation(self : RuntimeEvent) -> AppActivation? {
  match self {
    AppActivationReceived(activation) => Some(activation)
    _ => None
  }
}

///|
pub fn AppActivation::urls(self : AppActivation) -> Array[String] {
  self.urls.copy()
}

///|
pub fn AppActivation::files(self : AppActivation) -> Array[String] {
  self.files.copy()
}

///|
pub fn AppActivation::reopen(self : AppActivation) -> Bool {
  self.reopen
}

///|
pub fn RuntimeEvent::notification_result(
  self : RuntimeEvent,
) -> NativeNotificationResult? {
  match self {
    NotificationResult(result) => Some(result)
    _ => None
  }
}

///|
pub fn RuntimeEvent::notification_click(self : RuntimeEvent) -> String?? {
  match self {
    NotificationClicked(payload) => Some(payload)
    _ => None
  }
}

///|
pub fn RuntimeWaitReady::mask(self : RuntimeWaitReady) -> Int {
  self.mask
}

///|
pub fn RuntimeWaitReady::has_event(self : RuntimeWaitReady) -> Bool {
  self.mask.land(runtime_wait_event) != 0
}

///|
pub fn RuntimeWaitReady::has_platform(self : RuntimeWaitReady) -> Bool {
  self.mask.land(runtime_wait_platform) != 0
}

///|
pub fn RuntimeWaitReady::is_timeout(self : RuntimeWaitReady) -> Bool {
  self.mask == runtime_wait_none
}

///|
pub fn BridgeRequest::request_id(self : BridgeRequest) -> Int64 {
  self.request_id
}

///|
pub fn BridgeRequest::window(self : BridgeRequest) -> Int64 {
  self.window
}

///|
pub fn BridgeRequest::op(self : BridgeRequest) -> String {
  self.op
}

///|
pub fn BridgeRequest::payload(self : BridgeRequest) -> Json {
  self.payload
}

///|
pub fn BridgeRequest::page_instance(self : BridgeRequest) -> String? {
  self.page_instance
}

///|
pub fn BridgeRequest::source_origin(self : BridgeRequest) -> String {
  self.source_origin
}

///|
priv enum RuntimeLifecycleState {
  RuntimeActive = 0
  RuntimeDestroying = 1
  RuntimeDestroyed = 2
}

///|
priv enum WindowLifecycleState {
  WindowLive = 0
  WindowCloseRequested = 1
  WindowDestroying = 2
  WindowDestroyed = 3
}

///|
struct Runtime {
  mut handle : @native_ffi.RuntimeHandle
  mut lifecycle : RuntimeLifecycleState
}

///|
struct Window {
  mut handle : @native_ffi.WindowHandle
  id : Int64
  mut lifecycle : WindowLifecycleState
}

///|
struct WindowRef {
  handle : @native_ffi.WindowHandle
  id : Int64
}

///|
pub(all) struct TitlebarArea {
  x : Double
  y : Double
  width : Double
  height : Double
} derive(ToJson)

///|
pub extend TitlebarArea with ToJson::{to_json}

///|
pub impl Eq for WindowRef with fn equal(self : WindowRef, other : WindowRef) -> Bool {
  self.id == other.id
}

///|
pub impl Debug for WindowRef with fn to_repr(self : WindowRef) -> Repr {
  Repr::literal("WindowRef(\{self.id})")
}

///|
priv enum ImageLifecycleState {
  ImageLive = 0
  ImageDestroyed = 1
}

///|
struct NativeImage {
  mut handle : @native_ffi.ImageHandle
  mut lifecycle : ImageLifecycleState
}

///|
pub extend WindowRef with Eq::{not_equal, equal}

///|
pub extend WindowRef with Debug::{to_repr}

///|
pub(all) enum TitlebarStyle {
  Default
  Overlay
} derive(Debug, Eq)

///|
pub extend TitlebarStyle with Eq::{not_equal, equal}

///|
pub extend TitlebarStyle with Debug::{to_repr}

///|
pub(all) enum WindowTheme {
  Light = 1
  Dark = 2
} derive(Debug, Eq)

///|
pub extend WindowTheme with Eq::{not_equal, equal}

///|
pub extend WindowTheme with Debug::{to_repr}

///|
pub(all) enum WindowThemePreference {
  System = 0
  Light = 1
  Dark = 2
} derive(Debug, Eq)

///|
pub extend WindowThemePreference with Eq::{not_equal, equal}

///|
pub extend WindowThemePreference with Debug::{to_repr}

///|
fn WindowThemePreference::native_value(self : WindowThemePreference) -> Int {
  match self {
    System => 0
    Light => 1
    Dark => 2
  }
}

///|
/// Process-wide cache for `runtime_info`: the loaded runtime's identity and
/// feature set cannot change within a process, so feature probes reuse the
/// first successful result. Failures are not cached — callers keep the
/// previous retry-on-failure behavior. A concurrent double-fill is benign
/// (the query is pure and idempotent). The cached `features` array is shared
/// with callers; all current callers only read it.
let runtime_info_cache : Ref[RuntimeInfo?] = { val: None, }

///|
fn cached_runtime_info() -> RuntimeInfo raise NativeError {
  match runtime_info_cache.val {
    Some(info) => info
    None => {
      let info = runtime_info()
      runtime_info_cache.val = Some(info)
      info
    }
  }
}

///|
/// Controls how the configured width and height constrain native resizing.
pub(all) enum WindowSizeHint {
  Unconstrained
  Fixed
  Min
  Max
} derive(Debug, Eq)

///|
pub extend WindowSizeHint with Eq::{not_equal, equal}

///|
pub extend WindowSizeHint with Debug::{to_repr}

///|
pub(all) enum BrowserPolicyMode {
  Allow
  Deny
  Ask
} derive(Debug, Eq)

///|
pub extend BrowserPolicyMode with Eq::{not_equal, equal}

///|
pub extend BrowserPolicyMode with Debug::{to_repr}

///|
pub(all) struct BrowserPolicy {
  navigation : BrowserPolicyMode
  new_window : BrowserPolicyMode
  download : BrowserPolicyMode
  certificate : BrowserPolicyMode
  media : BrowserPolicyMode
  devtools : Bool
} derive(Debug, Eq)

///|
pub extend BrowserPolicy with Eq::{not_equal, equal}

///|
pub extend BrowserPolicy with Debug::{to_repr}

///|
pub fn BrowserPolicy::BrowserPolicy(
  navigation? : BrowserPolicyMode = BrowserPolicyMode::Allow,
  new_window? : BrowserPolicyMode = BrowserPolicyMode::Deny,
  download? : BrowserPolicyMode = BrowserPolicyMode::Deny,
  certificate? : BrowserPolicyMode = BrowserPolicyMode::Deny,
  media? : BrowserPolicyMode = BrowserPolicyMode::Deny,
  devtools? : Bool = false,
) -> BrowserPolicy {
  { navigation, new_window, download, certificate, media, devtools, }
}

///|
pub fn bridge_permission_grants_supported() -> Bool {
  let info = cached_runtime_info() catch { _ => return false }
  info.features.contains("bridge_permission_grants")
}

///|
/// Controls whether and where CEF exposes its remote debugging endpoint.
pub(all) enum RemoteDebugging {
  Disabled
  Ephemeral
  Fixed(Int)
} derive(Debug, Eq)

///|
pub extend RemoteDebugging with Eq::{not_equal, equal}

///|
pub extend RemoteDebugging with Debug::{to_repr}

///|
struct RuntimeConfig {
  use_bundled : Bool
  headless : Bool
  accessibility_mode : AccessibilityMode
  persist_session_cookies : Bool
  runtime_root : String?
  helper_path : String?
  resources_dir : String?
  locales_dir : String?
  cache_dir : String?
  locale : String?
  accept_languages : Array[String]
  framework_dialog_ok_label : String?
  framework_dialog_cancel_label : String?
  remote_debugging : RemoteDebugging
} derive(Debug, Eq)

///|
pub extend RuntimeConfig with Eq::{not_equal, equal}

///|
pub extend RuntimeConfig with Debug::{to_repr}

///|
struct WindowConfig {
  title : String
  width : Int
  height : Int
  initial_url : String
  size_hint : WindowSizeHint
  titlebar_style : TitlebarStyle
  theme_preference : WindowThemePreference
  browser : BrowserPolicy
  bridge : BridgeConfig?
  framework_titlebar_minimize_label : String?
  framework_titlebar_maximize_label : String?
  framework_titlebar_restore_label : String?
  framework_titlebar_close_label : String?
} derive(Debug, Eq)

///|
pub extend WindowConfig with Eq::{not_equal, equal}

///|
pub extend WindowConfig with Debug::{to_repr}

///|
/// Builds an explicit native runtime configuration.
///
/// Set `headless` to enable CEF off-screen rendering for every window created
/// by this runtime. Remote debugging remains independently configurable. Omit
/// `cache_dir` for an isolated temporary browser profile, or provide an
/// absolute, process-exclusive path for persistent browser state.
pub fn RuntimeConfig::RuntimeConfig(
  runtime_root? : String,
  helper_path? : String,
  resources_dir? : String,
  locales_dir? : String,
  cache_dir? : String,
  locale? : @locale.Locale,
  accept_languages? : Array[@locale.Locale] = [],
  remote_debugging? : RemoteDebugging = Disabled,
  headless? : Bool = false,
  accessibility_mode? : AccessibilityMode = Automatic,
  persist_session_cookies? : Bool = true,
) -> RuntimeConfig {
  {
    use_bundled: false,
    headless,
    accessibility_mode,
    persist_session_cookies,
    runtime_root,
    helper_path,
    resources_dir,
    locales_dir,
    cache_dir,
    locale: locale.map(value => value.to_string()),
    accept_languages: accept_languages.map(value => value.to_string()),
    framework_dialog_ok_label: Some("OK"),
    framework_dialog_cancel_label: Some("Cancel"),
    remote_debugging,
  }
}

///|
/// `helper_path`, when set, overrides the subprocess executable the bundled
/// runtime discovers. Packaged macOS applications automatically use their
/// nested base Helper app. Set `headless` to enable CEF off-screen rendering
/// for every window. Omit `cache_dir` for an isolated temporary browser
/// profile, or provide an absolute, process-exclusive path for persistence.
pub fn RuntimeConfig::bundled(
  helper_path? : String,
  cache_dir? : String,
  locale? : @locale.Locale,
  accept_languages? : Array[@locale.Locale] = [],
  remote_debugging? : RemoteDebugging = Disabled,
  headless? : Bool = false,
  accessibility_mode? : AccessibilityMode = Automatic,
  persist_session_cookies? : Bool = true,
) -> RuntimeConfig {
  {
    use_bundled: true,
    headless,
    accessibility_mode,
    persist_session_cookies,
    runtime_root: None,
    helper_path,
    resources_dir: None,
    locales_dir: None,
    cache_dir,
    locale: locale.map(value => value.to_string()),
    accept_languages: accept_languages.map(value => value.to_string()),
    framework_dialog_ok_label: Some("OK"),
    framework_dialog_cancel_label: Some("Cancel"),
    remote_debugging,
  }
}

///|
pub fn WindowConfig::WindowConfig(
  title? : String = "Proton",
  width? : Int = 800,
  height? : Int = 600,
  initial_url? : String = "about:blank",
  size_hint? : WindowSizeHint = WindowSizeHint::Unconstrained,
  titlebar_style? : TitlebarStyle = TitlebarStyle::Default,
  theme? : WindowThemePreference = WindowThemePreference::System,
  browser? : BrowserPolicy = BrowserPolicy(),
  bridge? : BridgeConfig,
) -> WindowConfig {
  {
    title,
    width,
    height,
    initial_url,
    size_hint,
    titlebar_style,
    theme_preference: theme,
    browser,
    bridge,
    framework_titlebar_minimize_label: Some("Minimize"),
    framework_titlebar_maximize_label: Some("Maximize"),
    framework_titlebar_restore_label: Some("Restore"),
    framework_titlebar_close_label: Some("Close"),
  }
}

///|
#doc(hidden)
pub fn RuntimeConfig::with_framework_dialog_labels(
  self : RuntimeConfig,
  ok : String,
  cancel : String,
) -> RuntimeConfig {
  {
    use_bundled: self.use_bundled,
    headless: self.headless,
    accessibility_mode: self.accessibility_mode,
    persist_session_cookies: self.persist_session_cookies,
    runtime_root: self.runtime_root,
    helper_path: self.helper_path,
    resources_dir: self.resources_dir,
    locales_dir: self.locales_dir,
    cache_dir: self.cache_dir,
    locale: self.locale,
    accept_languages: self.accept_languages,
    framework_dialog_ok_label: Some(ok),
    framework_dialog_cancel_label: Some(cancel),
    remote_debugging: self.remote_debugging,
  }
}

///|
#doc(hidden)
pub fn WindowConfig::with_framework_titlebar_labels(
  self : WindowConfig,
  minimize : String,
  maximize : String,
  restore : String,
  close : String,
) -> WindowConfig {
  {
    title: self.title,
    width: self.width,
    height: self.height,
    initial_url: self.initial_url,
    size_hint: self.size_hint,
    titlebar_style: self.titlebar_style,
    theme_preference: self.theme_preference,
    browser: self.browser,
    bridge: self.bridge,
    framework_titlebar_minimize_label: Some(minimize),
    framework_titlebar_maximize_label: Some(maximize),
    framework_titlebar_restore_label: Some(restore),
    framework_titlebar_close_label: Some(close),
  }
}

///|
/// Creates an application-level menu bar.
pub fn MenuBar::MenuBar(menus~ : Array[Menu]) -> MenuBar {
  { menus: menus.copy(), }
}

///|
/// Creates a top-level menu.
pub fn Menu::Menu(label : String, items~ : Array[MenuItem]) -> Menu {
  { label: Some(label), role: None, items: Some(items.copy()), }
}

///|
/// Creates a standard top-level menu. Omitted items select the role defaults;
/// an explicit item array replaces those defaults exactly.
pub fn Menu::role(
  role : MenuRole,
  label? : String,
  items? : Array[MenuItem],
) -> Menu {
  { label, role: Some(role), items: items.map(items => items.copy()), }
}

///|
/// Creates an app command item. Activating it emits `menu_command`. Passing
/// `checked` creates a checkbox command item; omitting it creates a normal
/// command item.
pub fn MenuItem::command(
  id : String,
  label : String,
  key? : String,
  enabled? : Bool = true,
  visible? : Bool = true,
  checked? : Bool,
) -> MenuItem {
  {
    kind: Command,
    id: Some(id),
    label: Some(label),
    key,
    role: None,
    submenu: None,
    enabled,
    visible,
    checked,
  }
}

///|
/// Creates a menu separator.
pub fn MenuItem::separator() -> MenuItem {
  {
    kind: Separator,
    id: None,
    label: None,
    key: None,
    role: None,
    submenu: None,
    enabled: true,
    visible: true,
    checked: None,
  }
}

///|
/// Creates an item backed by a platform menu role such as `close` or `quit`.
pub fn MenuItem::role(
  role : MenuItemRole,
  label? : String,
  key? : String,
) -> MenuItem {
  {
    kind: Role,
    id: None,
    label,
    key,
    role: Some(role),
    submenu: None,
    enabled: true,
    visible: true,
    checked: None,
  }
}

///|
/// Creates a nested submenu item with its own set of items.
pub fn MenuItem::submenu(label : String, items~ : Array[MenuItem]) -> MenuItem {
  {
    kind: Submenu,
    id: None,
    label: None,
    key: None,
    role: None,
    submenu: Some({ label: Some(label), role: None, items: Some(items.copy()), }),
    enabled: true,
    visible: true,
    checked: None,
  }
}

///|
#doc(hidden)
pub fn MenuBar::definitions(self : MenuBar) -> Array[Menu] {
  self.menus.copy()
}

///|
#doc(hidden)
pub fn Menu::definition(self : Menu) -> (MenuRole?, String?, Array[MenuItem]?) {
  (self.role, self.label, self.items.map(items => items.copy()))
}

///|
#doc(hidden)
pub fn MenuItem::definition(
  self : MenuItem,
) -> (String, String?, String?, String?, MenuItemRole?, Menu?) {
  let kind = match self.kind {
    Command => "command"
    Separator => "separator"
    Role => "role"
    Submenu => "submenu"
  }
  (kind, self.id, self.label, self.key, self.role, self.submenu)
}

///|
#doc(hidden)
pub fn MenuItem::state_definition(self : MenuItem) -> (Bool, Bool, Bool?) {
  (self.enabled, self.visible, self.checked)
}

///|
pub fn WindowRef::unsafe_from_handle(
  handle : @native_ffi.WindowHandle,
) -> WindowRef {
  WindowRef::{ handle, id: @native_ffi.window_logical_id(handle), }
}

///|
#doc(hidden)
pub fn WindowRef::invalid() -> WindowRef {
  WindowRef::unsafe_from_handle(@native_ffi.window_null())
}

///|
pub fn BridgeConfig::BridgeConfig(
  grants~ : Array[BridgeGrantConfig],
  max_payload_bytes? : Int = 1048576,
) -> BridgeConfig {
  { max_payload_bytes, grants: grants.map(fn(grant) { grant.copy() }), }
}

///|
pub fn BridgeGrantConfig::BridgeGrantConfig(
  source_origin : String,
  ops~ : Array[String],
  extensions? : Array[BridgeExtensionConfig] = [],
  initialization_units? : Array[BridgeInitializationUnit] = [],
) -> BridgeGrantConfig {
  {
    source_origin,
    ops: copy_strings(ops),
    extensions: extensions.map(fn(extension) { extension.copy() }),
    initialization_units: initialization_units.map(fn(unit) { unit.copy() }),
  }
}

///|
pub fn BridgeExtensionConfig::BridgeExtensionConfig(
  js_namespace : String,
  apis~ : Array[String],
) -> BridgeExtensionConfig {
  { js_namespace, apis: copy_strings(apis), }
}

///|
pub fn BridgeInitializationUnit::BridgeInitializationUnit(
  owner : String,
  name : String,
  source : String,
) -> BridgeInitializationUnit {
  { owner, name, source, }
}

///|
fn BridgeInitializationUnit::copy(
  self : BridgeInitializationUnit,
) -> BridgeInitializationUnit {
  { owner: self.owner, name: self.name, source: self.source, }
}

///|
fn BridgeExtensionConfig::copy(
  self : BridgeExtensionConfig,
) -> BridgeExtensionConfig {
  { js_namespace: self.js_namespace, apis: copy_strings(self.apis), }
}

///|
fn BridgeGrantConfig::copy(self : BridgeGrantConfig) -> BridgeGrantConfig {
  BridgeGrantConfig(
    self.source_origin,
    ops=self.ops,
    extensions=self.extensions,
    initialization_units=self.initialization_units,
  )
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  values.map(fn(value) { value })
}

///|
priv enum ViewLifecycleState {
  ViewLive = 0
  ViewDestroying = 1
  ViewDestroyed = 2
}

///|
/// An owned native web contents view hosted inside a window's content area.
struct View {
  mut handle : @native_ffi.ViewHandle
  id : Int64
  mut lifecycle : ViewLifecycleState
}

///|
/// A point-in-time web contents view state snapshot. Bounds use a top-left
/// origin in the owning window's content coordinate space.
pub(all) struct ViewState {
  x : Int
  y : Int
  width : Int
  height : Int
  visible : Bool
  z_order : Int
} derive(Debug, Eq)

///|
pub extend ViewState with Eq::{not_equal, equal}

///|
pub extend ViewState with Debug::{to_repr}

///|
/// Native configuration for one web contents view. `width` and `height` are
/// required because the native browser needs an initial rectangle; `x`/`y`
/// default to `0`, `visible` to `true`, `z_order` to `0`, and `initial_url`
/// to `about:blank`. Views stack above the window's main browser, ordered by
/// ascending `z_order`.
struct ViewConfig {
  x : Int
  y : Int
  width : Int
  height : Int
  visible : Bool
  z_order : Int
  initial_url : String
  background_color : String?
} derive(Debug, Eq)

///|
pub extend ViewConfig with Eq::{not_equal, equal}

///|
pub extend ViewConfig with Debug::{to_repr}

///|
pub fn ViewConfig::ViewConfig(
  width~ : Int,
  height~ : Int,
  x? : Int = 0,
  y? : Int = 0,
  visible? : Bool = true,
  z_order? : Int = 0,
  initial_url? : String = "about:blank",
  background_color? : String,
) -> ViewConfig {
  { x, y, width, height, visible, z_order, initial_url, background_color, }
}

///|
/// Returns true when the loaded native runtime supports web contents views.
pub fn web_contents_view_supported() -> Bool {
  let info = cached_runtime_info() catch { _ => return false }
  info.features.contains("web_contents_view")
}

///|
