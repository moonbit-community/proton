///|
/// Failures at Proton's private MoonBit/native boundary.
pub(all) suberror NativeError {
  /// A negative status returned by a private platform stub.
  Status(status~ : Int32, message~ : String)
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
pub fn NativeError::status(self : NativeError) -> Int32 {
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
/// Reports whether this build of Proton implements the requested operation on
/// the current platform.
pub fn NativeError::is_unsupported(self : NativeError) -> Bool {
  self.status() == proton_err_unsupported
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
pub fn NativeError::is_update_version_mismatch(self : NativeError) -> Bool {
  self.status() == proton_err_update_version_mismatch
}

///|
impl Show for NativeError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub(all) enum ProcessResult {
  MainProcess
  SubprocessHandled(Int32)
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
  mask : Int32
} derive(Debug, Eq)

///|
pub extend RuntimeWaitReady with Eq::{not_equal, equal}

///|
pub extend RuntimeWaitReady with Debug::{to_repr}

///|
/// Inputs forwarded by a second operating-system application instance.
pub(all) struct AppActivation {
  abi_version : Int32
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
/// Appearance snapshot carried by a native theme change event. The values are
/// the same ones `native_theme_query` reports, captured when the operating
/// system appearance changed so the event needs no second query.
pub(all) struct NativeThemeSnapshot {
  dark_colors : Bool
  high_contrast_colors : Bool
} derive(Debug, Eq)

///|
pub extend NativeThemeSnapshot with Eq::{not_equal, equal}

///|
pub extend NativeThemeSnapshot with Debug::{to_repr}

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
  AppActivationReceived(AppActivation, Int64)
  NativeThemeChanged(NativeThemeSnapshot)
  TaskbarButtonClicked(Int64, String)
  NotificationResult(NativeNotificationResult)
  NotificationClicked(String?)
  BrowserRequest(Int64, Int64?, NativeBrowserRequest)
  BrowserDownloadUpdated(Int64, Int64?, NativeDownloadUpdate)
  BrowserPdfPrinted(Int64, Int64?, NativePdfPrintResult)
  BrowserEvent(Int64, Int64?, NativeBrowserEvent)
  ViewClosed(Int64, Int64)
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
pub(all) struct PdfPrintSettings {
  landscape : Bool
  print_background : Bool
  scale : Double
  paper_width : Double
  paper_height : Double
  prefer_css_page_size : Bool
  margin_type : Int32
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
pub extend RuntimeEvent with Eq::{not_equal, equal}

///|
pub extend RuntimeEvent with Debug::{to_repr}

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
  NewWindow(request_id~ : Int64, url~ : String, user_gesture~ : Bool)
  Download(
    request_id~ : Int64,
    download_id~ : Int32,
    url~ : String,
    suggested_name~ : String
  )
  Certificate(request_id~ : Int64, url~ : String, error_code~ : Int32)
  Media(request_id~ : Int64, origin~ : String, permissions~ : Int32)
} derive(Debug, Eq)

///|
pub extend NativeBrowserRequest with Eq::{not_equal, equal}

///|
pub extend NativeBrowserRequest with Debug::{to_repr}

///|
pub(all) struct NativeDownloadUpdate {
  download_id : Int32
  state : String
  received_bytes : Int64
  total_bytes : Int64
  percent : Int32
} derive(Debug, Eq)

///|
pub extend NativeDownloadUpdate with Eq::{not_equal, equal}

///|
pub extend NativeDownloadUpdate with Debug::{to_repr}

///|
pub(all) struct NativePdfPrintResult {
  request_id : Int32
  path : String
  success : Bool
} derive(Debug, Eq)

///|
pub extend NativePdfPrintResult with Eq::{not_equal, equal}

///|
pub extend NativePdfPrintResult with Debug::{to_repr}

///|
/// One entry of Chromium's navigation history. `transition` is the
/// page-transition type and `qualifiers` is the flag set Proton maps from
/// Chromium's transition flags.
pub(all) struct NavigationEntry {
  url : String
  display_url : String
  original_url : String
  title : String
  transition : Int32
  qualifiers : Int32
  has_post_data : Bool
  http_status_code : Int32
} derive(Debug, Eq, FromJson)

///|
pub extend NavigationEntry with Eq::{not_equal, equal}

///|
pub extend NavigationEntry with Debug::{to_repr}

///|
pub extend NavigationEntry with FromJson::{from_json}

///|
/// Navigation-history snapshot: every entry in order plus the active index,
/// or -1 while the browser has no entries.
pub(all) struct NavigationHistory {
  entries : Array[NavigationEntry]
  active_index : Int32
} derive(Debug, Eq, FromJson)

///|
pub extend NavigationHistory with Eq::{not_equal, equal}

///|
pub extend NavigationHistory with Debug::{to_repr}

///|
pub extend NavigationHistory with FromJson::{from_json}

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
/// Normal outcomes of checking whether an enqueued request may still run.
pub(all) enum BridgeRequestAdmission {
  Dispatchable
  Gone
  WindowUnavailable
  PageUnavailable
}

///|
pub(all) enum BridgeResponse {
  Ok(request_id~ : Int64, payload~ : Json)
  Err(request_id~ : Int64, code~ : String, message~ : String, detail~ : String?)
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
fn DialogLevel::native_value(self : DialogLevel) -> Int32 {
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
  LoadFailed(String, Int32, String)
  FindResult(FindInPageResult)
  ResourceResponse(String, Int32)
  ResourceCompleted(String, Int32, Int64)
  ResourceRequested(String, String, Bool)
  RendererProcessTerminated(String, Int32, Int32, String)
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
fn CookieSameSite::native_value(self : CookieSameSite) -> Int32 {
  match self {
    Unspecified => 0
    NoRestriction => 1
    Lax => 2
    Strict => 3
  }
}

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
pub(all) struct BridgeConfig {
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
    AppActivationReceived(_, _) => "app_activation"
    NativeThemeChanged(_) => "native_theme_changed"
    TaskbarButtonClicked(_, _) => "taskbar_button_clicked"
    NotificationResult(_) => "notification_result"
    NotificationClicked(_) => "notification_clicked"
    BrowserRequest(_, _, NewWindow(..)) => "browser_new_window_requested"
    BrowserRequest(_, _, Download(..)) => "browser_download_requested"
    BrowserRequest(_, _, Certificate(..)) => "browser_certificate_error"
    BrowserRequest(_, _, Media(..)) => "browser_media_permission_requested"
    BrowserDownloadUpdated(_, _, _) => "browser_download_updated"
    BrowserPdfPrinted(_, _, _) => "browser_pdf_print_finished"
    BrowserEvent(_, _, LoadingChanged(_)) => "browser_loading_changed"
    BrowserEvent(_, _, Navigated(_)) => "browser_navigated"
    BrowserEvent(_, _, TitleUpdated(_)) => "browser_title_updated"
    BrowserEvent(_, _, LoadFailed(_, _, _)) => "browser_load_failed"
    BrowserEvent(_, _, FindResult(_)) => "browser_found_in_page"
    BrowserEvent(_, _, ResourceResponse(_, _)) => "browser_resource_response"
    BrowserEvent(_, _, ResourceCompleted(_, _, _)) =>
      "browser_resource_completed"
    BrowserEvent(_, _, ResourceRequested(_, _, _)) =>
      "browser_resource_requested"
    BrowserEvent(_, _, RendererProcessTerminated(_, _, _, _)) =>
      "browser_renderer_process_terminated"
    ViewClosed(_, _) => "view_closed"
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
    | BrowserRequest(window, _, _)
    | BrowserDownloadUpdated(window, _, _)
    | BrowserPdfPrinted(window, _, _)
    | BrowserEvent(window, _, _)
    | ViewClosed(window, _)
    | TaskbarButtonClicked(window, _) => Some(window)
    ResourceRequested(request) => Some(request.window)
    MenuCommand(_, window) => window
    DialogCompleted(completion) => completion.window
    CookieGetCompleted(completion) => Some(completion.window)
    BridgeRequestReceived(_)
    | BridgeRequestCancelled(_)
    | ResourceRequestCancelled(_)
    | LaunchInput(_)
    | AppActivationReceived(_, _)
    | NativeThemeChanged(_)
    | NotificationResult(_)
    | NotificationClicked(_)
    | QuitRequested => None
  }
}

///|
/// Returns the web contents view associated with this event when one exists.
pub fn RuntimeEvent::view_id(self : RuntimeEvent) -> Int64? {
  match self {
    BrowserEvent(_, view, _)
    | BrowserRequest(_, view, _)
    | BrowserDownloadUpdated(_, view, _)
    | BrowserPdfPrinted(_, view, _) => view
    ViewClosed(_, view) => Some(view)
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
pub(all) struct BrowserEventInfo {
  url : String?
  title : String?
  is_loading : Bool?
  error_code : Int32?
  error_text : String?
  received_bytes : Int64?
} derive(Debug, Eq)

///|
pub extend BrowserEventInfo with Eq::{not_equal, equal}

///|
pub extend BrowserEventInfo with Debug::{to_repr}

///|
pub(all) struct RendererProcessTerminationInfo {
  url : String
  status : Int32
  error_code : Int32
  detail : String
} derive(Debug, Eq)

///|
pub extend RendererProcessTerminationInfo with Eq::{not_equal, equal}

///|
pub extend RendererProcessTerminationInfo with Debug::{to_repr}

///|
/// Returns the web contents event payload when this event carries one.
pub fn RuntimeEvent::browser_event(self : RuntimeEvent) -> BrowserEventInfo? {
  match self {
    BrowserEvent(_, _, LoadingChanged(is_loading)) =>
      Some({
        url: None,
        title: None,
        is_loading: Some(is_loading),
        error_code: None,
        error_text: None,
        received_bytes: None,
      })
    BrowserEvent(_, _, Navigated(url)) =>
      Some({
        url: Some(url),
        title: None,
        is_loading: None,
        error_code: None,
        error_text: None,
        received_bytes: None,
      })
    BrowserEvent(_, _, TitleUpdated(title)) =>
      Some({
        url: None,
        title: Some(title),
        is_loading: None,
        error_code: None,
        error_text: None,
        received_bytes: None,
      })
    BrowserEvent(_, _, LoadFailed(url, error_code, error_text)) =>
      Some({
        url: Some(url),
        title: None,
        is_loading: None,
        error_code: Some(error_code),
        error_text: Some(error_text),
        received_bytes: None,
      })
    BrowserEvent(_, _, ResourceResponse(url, status)) =>
      Some({
        url: Some(url),
        title: None,
        is_loading: None,
        error_code: Some(status),
        error_text: None,
        received_bytes: None,
      })
    BrowserEvent(_, _, ResourceCompleted(url, status, bytes)) =>
      Some({
        url: Some(url),
        title: None,
        is_loading: None,
        error_code: Some(status),
        error_text: None,
        received_bytes: Some(bytes),
      })
    BrowserEvent(_, _, ResourceRequested(url, request_method, will_cancel)) =>
      Some({
        url: Some(url),
        title: Some(request_method),
        is_loading: Some(will_cancel),
        error_code: None,
        error_text: None,
        received_bytes: None,
      })
    _ => None
  }
}

///|
/// Returns renderer termination details when this event carries them.
pub fn RuntimeEvent::renderer_process_termination(
  self : RuntimeEvent,
) -> RendererProcessTerminationInfo? {
  match self {
    BrowserEvent(
      _,
      _,
      RendererProcessTerminated(url, status, error_code, detail)
    ) => Some({ url, status, error_code, detail, })
    _ => None
  }
}

///|
pub fn RuntimeEvent::find_in_page_result(
  self : RuntimeEvent,
) -> FindInPageResult? {
  match self {
    BrowserEvent(_, _, FindResult(result)) => Some(result)
    _ => None
  }
}

///|
pub fn RuntimeEvent::is_view_closed(self : RuntimeEvent) -> Bool {
  self is ViewClosed(_, _)
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
    BrowserRequest(_, _, request) => Some(request)
    _ => None
  }
}

///|
pub fn RuntimeEvent::browser_download_update(
  self : RuntimeEvent,
) -> NativeDownloadUpdate? {
  match self {
    BrowserDownloadUpdated(_, _, update) => Some(update)
    _ => None
  }
}

///|
pub fn RuntimeEvent::pdf_print_result(
  self : RuntimeEvent,
) -> NativePdfPrintResult? {
  match self {
    BrowserPdfPrinted(_, _, result) => Some(result)
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
    AppActivationReceived(activation, _) => Some(activation)
    _ => None
  }
}

///|
/// Returns zero for locally generated launch input without a forwarding peer.
pub fn RuntimeEvent::app_activation_request_id(self : RuntimeEvent) -> Int64 {
  match self {
    AppActivationReceived(_, request_id) => request_id
    _ => 0
  }
}

///|
/// Returns the snapshot captured when the operating system appearance changed.
pub fn RuntimeEvent::native_theme_change(
  self : RuntimeEvent,
) -> NativeThemeSnapshot? {
  match self {
    NativeThemeChanged(snapshot) => Some(snapshot)
    _ => None
  }
}

///|
/// Returns the button identifier when this event reports a taskbar
/// thumbnail-toolbar click. The owning window comes from `window_id()`.
pub fn RuntimeEvent::taskbar_button_id(self : RuntimeEvent) -> String? {
  match self {
    TaskbarButtonClicked(_, id) => Some(id)
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
pub fn RuntimeWaitReady::mask(self : RuntimeWaitReady) -> Int32 {
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
  runtime : Runtime
  mut handle : @native_ffi.WindowHandle
  id : Int64
  mut lifecycle : WindowLifecycleState
  mut close_interception_enabled : Bool
}

///|
struct WindowRef {
  window : Window?
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
fn WindowThemePreference::native_value(self : WindowThemePreference) -> Int32 {
  match self {
    System => 0
    Light => 1
    Dark => 2
  }
}

///|
fn ProgressBarMode::native_value(self : ProgressBarMode) -> Int32 {
  match self {
    Automatic => 0
    Normal => 1
    Indeterminate => 2
    Error => 3
    Paused => 4
    Cleared => 5
  }
}

///|
/// Native flag bits, matching the PROTON_THUMBAR_FLAG_* values in the C ABI.
fn ThumbarButtonFlag::native_value(self : ThumbarButtonFlag) -> Int32 {
  match self {
    Disabled => 0x1
    DismissOnClick => 0x2
    NoBackground => 0x4
    Hidden => 0x8
    NonInteractive => 0x10
  }
}

///|
/// One taskbar thumbnail-toolbar button. `id` identifies the button in the
/// click event the application receives.
pub(all) struct ThumbarButton {
  id : String
  icon : NativeImage
  tooltip : String
  flags : Array[ThumbarButtonFlag]
}

///|
fn JumpListItemKind::native_value(self : JumpListItemKind) -> Int32 {
  match self {
    Task => 0
    Separator => 1
    File => 2
  }
}

///|
fn JumpListCategoryKind::native_value(self : JumpListCategoryKind) -> Int32 {
  match self {
    Tasks => 0
    Custom => 1
    Recent => 2
    Frequent => 3
  }
}

///|
fn jump_list_result_from_code(code : Int32) -> JumpListResult {
  match code {
    0 => Ok
    2 => InvalidSeparator
    3 => FileTypeRegistrationError
    4 => CustomCategoryAccessDenied
    5 => Unsupported
    _ => Error
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
  navigation~ : BrowserPolicyMode = BrowserPolicyMode::Allow,
  new_window~ : BrowserPolicyMode = BrowserPolicyMode::Deny,
  download~ : BrowserPolicyMode = BrowserPolicyMode::Deny,
  certificate~ : BrowserPolicyMode = BrowserPolicyMode::Deny,
  media~ : BrowserPolicyMode = BrowserPolicyMode::Deny,
  devtools~ : Bool = false,
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
  Fixed(Int32)
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
  proxy_server : String?
  proxy_bypass : String?
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
  width : Int32
  height : Int32
  initial_url : String
  size_hint : WindowSizeHint
  titlebar_style : TitlebarStyle
  traffic_light_position : (Int32, Int32)?
  theme_preference : WindowThemePreference
  browser : BrowserPolicy
  bridge : BridgeConfig?
  web_request_cancel_prefixes : Array[String]
  web_request_redirect_prefixes : Array[(String, String)]
  web_request_header_prefixes : Array[(String, String, String)]
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
  accept_languages~ : Array[@locale.Locale] = [],
  proxy_server? : String,
  proxy_bypass? : String,
  remote_debugging~ : RemoteDebugging = Disabled,
  headless~ : Bool = false,
  accessibility_mode~ : AccessibilityMode = Automatic,
  persist_session_cookies~ : Bool = true,
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
    proxy_server,
    proxy_bypass,
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
  accept_languages~ : Array[@locale.Locale] = [],
  proxy_server? : String,
  proxy_bypass? : String,
  remote_debugging~ : RemoteDebugging = Disabled,
  headless~ : Bool = false,
  accessibility_mode~ : AccessibilityMode = Automatic,
  persist_session_cookies~ : Bool = true,
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
    proxy_server,
    proxy_bypass,
    framework_dialog_ok_label: Some("OK"),
    framework_dialog_cancel_label: Some("Cancel"),
    remote_debugging,
  }
}

///|
pub fn WindowConfig::WindowConfig(
  title~ : String = "Proton",
  width~ : Int32 = 800,
  height~ : Int32 = 600,
  initial_url~ : String = "about:blank",
  size_hint~ : WindowSizeHint = WindowSizeHint::Unconstrained,
  titlebar_style~ : TitlebarStyle = TitlebarStyle::Default,
  traffic_light_position? : (Int32, Int32),
  theme~ : WindowThemePreference = WindowThemePreference::System,
  browser~ : BrowserPolicy = BrowserPolicy(),
  bridge? : BridgeConfig,
  web_request_cancel_prefixes~ : Array[String] = [],
  web_request_redirect_prefixes~ : Array[(String, String)] = [],
  web_request_header_prefixes~ : Array[(String, String, String)] = [],
) -> WindowConfig {
  {
    title,
    width,
    height,
    initial_url,
    size_hint,
    titlebar_style,
    traffic_light_position,
    theme_preference: theme,
    browser,
    bridge,
    web_request_cancel_prefixes,
    web_request_redirect_prefixes,
    web_request_header_prefixes,
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
    proxy_server: self.proxy_server,
    proxy_bypass: self.proxy_bypass,
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
    traffic_light_position: self.traffic_light_position,
    theme_preference: self.theme_preference,
    browser: self.browser,
    bridge: self.bridge,
    web_request_cancel_prefixes: self.web_request_cancel_prefixes,
    web_request_redirect_prefixes: self.web_request_redirect_prefixes,
    web_request_header_prefixes: self.web_request_header_prefixes,
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
  enabled~ : Bool = true,
  visible~ : Bool = true,
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
#doc(hidden)
pub fn WindowRef::invalid() -> WindowRef {
  WindowRef::{ window: None, id: proton_invalid_handle, }
}

///|
pub fn BridgeConfig::BridgeConfig(
  grants~ : Array[BridgeGrantConfig],
) -> BridgeConfig {
  { grants: grants.map(fn(grant) { grant.copy() }), }
}

///|
pub fn BridgeGrantConfig::BridgeGrantConfig(
  source_origin : String,
  ops~ : Array[String],
  extensions~ : Array[BridgeExtensionConfig] = [],
  initialization_units~ : Array[BridgeInitializationUnit] = [],
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
  window : Window
  mut handle : @native_ffi.ViewHandle
  id : Int64
  mut lifecycle : ViewLifecycleState
}

///|
/// Native configuration for one web contents view. `width` and `height` are
/// required because the native browser needs an initial rectangle; `x`/`y`
/// default to `0`, `visible` to `true`, `z_order` to `0`, and `initial_url`
/// to `about:blank`. Views stack above the window's main browser, ordered by
/// ascending `z_order`.
struct ViewConfig {
  x : Int32
  y : Int32
  width : Int32
  height : Int32
  visible : Bool
  z_order : Int32
  initial_url : String
  background_color : String?
  navigation : BrowserPolicyMode
  new_window : BrowserPolicyMode
} derive(Debug, Eq)

///|
pub extend ViewConfig with Eq::{not_equal, equal}

///|
pub extend ViewConfig with Debug::{to_repr}

///|
pub fn ViewConfig::ViewConfig(
  width~ : Int32,
  height~ : Int32,
  x~ : Int32 = 0,
  y~ : Int32 = 0,
  visible~ : Bool = true,
  z_order~ : Int32 = 0,
  initial_url~ : String = "about:blank",
  background_color? : String,
  navigation~ : BrowserPolicyMode = Allow,
  new_window~ : BrowserPolicyMode = Deny,
) -> ViewConfig {
  {
    x,
    y,
    width,
    height,
    visible,
    z_order,
    initial_url,
    background_color,
    navigation,
    new_window,
  }
}

///|
/// Returns true when the loaded native runtime supports web contents views.
pub fn web_contents_view_supported() -> Bool {
  let info = cached_runtime_info() catch { _ => return false }
  info.features.contains("web_contents_view")
}

///|
/// A page operation target retaining its window or view owner.
pub(all) enum Contents {
  PrimaryPage(Window)
  ChildView(View)
}

///|
pub using @native_ffi {type BrowserOperation}

///|
pub using @types {
  type AccessibilityMode,
  type AnimationSettings,
  type AppTaskMetric,
  type AppTaskType,
  type BridgeDiagnostic,
  type BrowserState,
  type CookieSameSite,
  type FindInPageResult,
  type JumpListCategory,
  type JumpListCategoryKind,
  type JumpListItem,
  type JumpListItemKind,
  type JumpListResult,
  type MediaAccessKind,
  type MediaAccessStatus,
  type MenuItemRole,
  type MenuRole,
  type ProgressBarMode,
  type RuntimeLaunchInput,
  type ScreenInfo,
  type ThumbarButtonFlag,
  type TitlebarStyle,
  type ViewState,
  type WindowMonitor,
  type WindowSizeHint,
  type WindowState,
  type WindowTheme,
  type WindowThemePreference,
}
