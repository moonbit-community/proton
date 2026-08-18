///|
/// Failures at the MoonBit/native runtime boundary.
pub(all) suberror NativeError {
  /// A negative status returned by the public Proton C ABI.
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
  abi_version : Int
  runtime_available : Bool
  build_mode : String
  platform : String
  /// The prebuilt identifier this library was built as, such as
  /// `darwin-arm64`. Matches the platform keys in an update manifest.
  platform_id : String
  features : Array[String]
} derive(Debug, Eq, FromJson)

///|
pub extend RuntimeInfo with Eq::{not_equal, equal}

///|
pub extend RuntimeInfo with Debug::{to_repr}

///|
pub extend RuntimeInfo with FromJson::{from_json}

///|
pub(all) struct RuntimeWaitReady {
  mask : Int
} derive(Debug, Eq)

///|
pub extend RuntimeWaitReady with Eq::{not_equal, equal}

///|
pub extend RuntimeWaitReady with Debug::{to_repr}

///|
/// Inputs forwarded by a second operating-system application instance.
pub(all) struct AppActivation {
  abi_version : Int
  urls : Array[String]
  files : Array[String]
  reopen : Bool
} derive(Debug, Eq, ToJson)

///|
pub extend AppActivation with Eq::{not_equal, equal}

///|
pub extend AppActivation with Debug::{to_repr}

///|
pub extend AppActivation with ToJson::{to_json}

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
struct RuntimeEvent {
  event_type : String
  window : Int64?
  view : Int64?
  title : String?
  is_loading : Bool?
  state : WindowState?
  request_id : Int64?
  url : String?
  http_method : String?
  user_gesture : Bool?
  redirect : Bool?
  disposition : Int?
  download_id : Int?
  suggested_name : String?
  download_state : String?
  received_bytes : Int64?
  total_bytes : Int64?
  percent : Int?
  error_code : Int?
  permissions : Int?
  menu_command_id : String?
  revision : Int64?
  items : Array[String]
  ok : Bool?
  message : String?
} derive(Debug, Eq)

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
  Popup(
    request_id~ : Int64,
    url~ : String,
    disposition~ : Int,
    user_gesture~ : Bool
  )
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
pub(all) struct BridgeLifecycleState {
  abi_version : Int
  revision : String
  outcome : String
  page_instance : String
  url : String
  failure_pending : Bool
} derive(Debug, Eq, FromJson)

///|
pub extend BridgeLifecycleState with Eq::{not_equal, equal}

///|
pub extend BridgeLifecycleState with Debug::{to_repr}

///|
pub extend BridgeLifecycleState with FromJson::{from_json}

///|
pub(all) struct BridgeDiagnostic {
  abi_version : Int
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
} derive(Debug, Eq, FromJson)

///|
pub extend BridgeDiagnostic with Eq::{not_equal, equal}

///|
pub extend BridgeDiagnostic with Debug::{to_repr}

///|
pub extend BridgeDiagnostic with FromJson::{from_json}

///|
pub(all) struct BridgeRequest {
  request_id : Int64
  window : Int64
  op : String
  payload : Json
  page_instance : String?
  source_origin : String
} derive(Debug)

///|
pub extend BridgeRequest with Debug::{to_repr}

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
pub(all) enum DialogPollResult {
  Pending
  Ready(String)
} derive(Debug, Eq)

///|
pub extend DialogPollResult with Eq::{not_equal, equal}

///|
pub extend DialogPollResult with Debug::{to_repr}

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
} derive(Debug, Eq, FromJson)

///|
pub extend WindowMonitor with Eq::{not_equal, equal}

///|
pub extend WindowMonitor with Debug::{to_repr}

///|
pub extend WindowMonitor with FromJson::{from_json}

///|
/// A point-in-time native window state snapshot.
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
  theme : String
} derive(Debug, Eq, FromJson)

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
} derive(Debug, Eq, FromJson)

///|
pub extend ScreenInfo with Eq::{not_equal, equal}

///|
pub extend ScreenInfo with Debug::{to_repr}

///|
pub extend ScreenInfo with FromJson::{from_json}

///|
pub extend WindowState with Eq::{not_equal, equal}

///|
pub extend WindowState with Debug::{to_repr}

///|
pub extend WindowState with FromJson::{from_json}

///|
/// A native notification activation, optionally carrying its application
/// payload.
pub(all) struct NativeNotificationClick {
  payload : String?
} derive(Debug, Eq)

///|
pub extend NativeNotificationClick with Eq::{not_equal, equal}

///|
pub extend NativeNotificationClick with Debug::{to_repr}

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
  kind : String
  id : String?
  label : String?
  key : String?
  role : MenuItemRole?
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
  raw_json : String?
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
  self.event_type
}

///|
pub fn RuntimeEvent::has_window(self : RuntimeEvent) -> Bool {
  self.window is Some(_)
}

///|
/// Returns the window associated with this event when one exists. For an app
/// menu command this is the focused window at click time.
pub fn RuntimeEvent::window_id(self : RuntimeEvent) -> Int64? {
  self.window
}

///|
/// Returns the web contents view associated with this event when one exists.
pub fn RuntimeEvent::view_id(self : RuntimeEvent) -> Int64? {
  self.view
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
  if !self.event_type.has_prefix("view_") {
    return None
  }
  Some({
    url: self.url,
    title: self.title,
    is_loading: self.is_loading,
    error_code: self.error_code,
    error_text: self.message,
  })
}

///|
pub fn RuntimeEvent::is_window_created(self : RuntimeEvent) -> Bool {
  self.event_type == "window_created"
}

///|
pub fn RuntimeEvent::is_window_closed(self : RuntimeEvent) -> Bool {
  self.event_type == "window_closed"
}

///|
pub fn RuntimeEvent::window_state_change(self : RuntimeEvent) -> WindowState? {
  if self.event_type == "window_state_changed" {
    self.state
  } else {
    None
  }
}

///|
pub fn RuntimeEvent::window_close_request(self : RuntimeEvent) -> Int64? {
  if self.event_type == "window_close_requested" {
    self.request_id
  } else {
    None
  }
}

///|
pub fn RuntimeEvent::browser_request(
  self : RuntimeEvent,
) -> NativeBrowserRequest? {
  let request_id = self.request_id
  let url = self.url
  match (self.event_type, request_id, url) {
    ("browser_navigation_requested", Some(request_id), Some(url)) =>
      Some(
        Navigation(
          request_id~,
          url~,
          http_method=self.http_method.unwrap_or("GET"),
          user_gesture=self.user_gesture.unwrap_or(false),
          redirect=self.redirect.unwrap_or(false),
        ),
      )
    ("browser_popup_requested", Some(request_id), Some(url)) =>
      Some(
        Popup(
          request_id~,
          url~,
          disposition=self.disposition.unwrap_or(0),
          user_gesture=self.user_gesture.unwrap_or(false),
        ),
      )
    ("browser_download_requested", Some(request_id), Some(url)) =>
      Some(
        Download(
          request_id~,
          download_id=self.download_id.unwrap_or(0),
          url~,
          suggested_name=self.suggested_name.unwrap_or(""),
        ),
      )
    ("browser_certificate_error", Some(request_id), Some(url)) =>
      Some(
        Certificate(request_id~, url~, error_code=self.error_code.unwrap_or(0)),
      )
    ("browser_media_permission_requested", Some(request_id), Some(origin)) =>
      Some(
        Media(request_id~, origin~, permissions=self.permissions.unwrap_or(0)),
      )
    _ => None
  }
}

///|
pub fn RuntimeEvent::browser_download_update(
  self : RuntimeEvent,
) -> NativeDownloadUpdate? {
  guard self.event_type == "browser_download_updated" else { return None }
  match
    (
      self.download_id,
      self.download_state,
      self.received_bytes,
      self.total_bytes,
      self.percent,
    ) {
    (
      Some(download_id),
      Some(state),
      Some(received_bytes),
      Some(total_bytes),
      Some(percent),
    ) => Some({ download_id, state, received_bytes, total_bytes, percent })
    _ => None
  }
}

///|
pub fn RuntimeEvent::is_bridge_lifecycle_changed(self : RuntimeEvent) -> Bool {
  self.event_type == "bridge_lifecycle_changed"
}

///|
pub fn RuntimeEvent::bridge_request_cancellation(self : RuntimeEvent) -> Int64? {
  if self.event_type == "bridge_request_cancelled" {
    self.request_id
  } else {
    None
  }
}

///|
/// The command id for an app-menu command item click, or `None` for every
/// other event kind.
pub fn RuntimeEvent::menu_command_id(self : RuntimeEvent) -> String? {
  if self.event_type == "menu_command" {
    self.menu_command_id
  } else {
    None
  }
}

///|
/// Returns the typed application launch input carried by this event.
pub fn RuntimeEvent::launch_input(self : RuntimeEvent) -> RuntimeLaunchInput? {
  match self.event_type {
    "open_urls" => Some(RuntimeLaunchInput::OpenUrls(self.items.copy()))
    "open_files" => Some(RuntimeLaunchInput::OpenFiles(self.items.copy()))
    "reopen" => Some(RuntimeLaunchInput::Reopen)
    _ => None
  }
}

///|
pub fn RuntimeEvent::notification_result(
  self : RuntimeEvent,
) -> NativeNotificationResult? {
  guard self.event_type == "notification_result" else { return None }
  match self.ok {
    Some(true) => Some(NativeNotificationResult::Delivered)
    Some(false) =>
      Some(
        NativeNotificationResult::Failed(
          self.message.unwrap_or("notification delivery failed"),
        ),
      )
    None => None
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
pub fn RuntimeWaitReady::has_bridge(self : RuntimeWaitReady) -> Bool {
  self.mask.land(runtime_wait_bridge) != 0
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
  mut handle : Int64
  mut lifecycle : RuntimeLifecycleState
}

///|
struct Window {
  mut handle : Int64
  mut lifecycle : WindowLifecycleState
}

///|
struct WindowRef {
  handle : Int64
} derive(Debug, Eq)

///|
priv enum ImageLifecycleState {
  ImageLive = 0
  ImageDestroyed = 1
}

///|
struct NativeImage {
  mut handle : Int64
  mut lifecycle : ImageLifecycleState
}

///|
struct ImageSize {
  width : Int
  height : Int
} derive(FromJson, ToJson)

///|
pub extend ImageSize with ToJson::{to_json}

///|
pub extend ImageSize with FromJson::{from_json}

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
/// Process-wide cache for `runtime_info`: the loaded runtime's identity and
/// feature set cannot change within a process, so feature probes reuse the
/// first successful result. Failures are not cached — callers keep the
/// previous retry-on-failure behavior. A concurrent double-fill is benign
/// (the query is pure and idempotent). The cached `features` array is shared
/// with callers; all current callers only read it.
let runtime_info_cache : Ref[RuntimeInfo?] = { val: None }

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
fn titlebar_overlay_config_supported() -> Bool {
  let info = cached_runtime_info() catch { _ => return false }
  info.features.contains("titlebar_overlay")
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
  popup : BrowserPolicyMode
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
pub fn BrowserPolicy::new(
  navigation? : BrowserPolicyMode = BrowserPolicyMode::Allow,
  popup? : BrowserPolicyMode = BrowserPolicyMode::Deny,
  download? : BrowserPolicyMode = BrowserPolicyMode::Deny,
  certificate? : BrowserPolicyMode = BrowserPolicyMode::Deny,
  media? : BrowserPolicyMode = BrowserPolicyMode::Deny,
  devtools? : Bool = false,
) -> BrowserPolicy {
  { navigation, popup, download, certificate, media, devtools }
}

///|
fn window_size_hint_config_supported() -> Bool {
  let info = cached_runtime_info() catch { _ => return false }
  info.features.contains("window_size_hints")
}

///|
pub fn bridge_permission_grants_supported() -> Bool {
  let info = cached_runtime_info() catch { _ => return false }
  info.features.contains("bridge_permission_grants")
}

///|
struct RuntimeConfig {
  raw_json : String?
  use_bundled : Bool
  headless : Bool
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
  remote_debugging_port : Int
} derive(Debug, Eq)

///|
pub extend RuntimeConfig with Eq::{not_equal, equal}

///|
pub extend RuntimeConfig with Debug::{to_repr}

///|
struct WindowConfig {
  raw_json : String?
  title : String
  width : Int
  height : Int
  initial_url : String
  size_hint : WindowSizeHint
  titlebar_style : TitlebarStyle
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
pub fn RuntimeConfig::new(
  runtime_root? : String,
  helper_path? : String,
  resources_dir? : String,
  locales_dir? : String,
  cache_dir? : String,
  locale? : @locale.Locale,
  accept_languages? : Array[@locale.Locale] = [],
  remote_debugging_port? : Int = 0,
  headless? : Bool = false,
  persist_session_cookies? : Bool = true,
) -> RuntimeConfig {
  {
    raw_json: None,
    use_bundled: false,
    headless,
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
    remote_debugging_port,
  }
}

///|
/// Builds a runtime configuration from unchecked ABI JSON.
///
/// This bypasses typed locale and schema construction and is intended only
/// for low-level compatibility tests and native integration code.
pub fn RuntimeConfig::unsafe_from_json(raw_json : String) -> RuntimeConfig {
  {
    raw_json: Some(raw_json),
    use_bundled: false,
    headless: false,
    persist_session_cookies: true,
    runtime_root: None,
    helper_path: None,
    resources_dir: None,
    locales_dir: None,
    cache_dir: None,
    locale: None,
    accept_languages: [],
    framework_dialog_ok_label: None,
    framework_dialog_cancel_label: None,
    remote_debugging_port: 0,
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
  remote_debugging_port? : Int = 0,
  headless? : Bool = false,
  persist_session_cookies? : Bool = true,
) -> RuntimeConfig {
  {
    raw_json: None,
    use_bundled: true,
    headless,
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
    remote_debugging_port,
  }
}

///|
pub fn WindowConfig::new(
  title? : String = "Proton",
  width? : Int = 800,
  height? : Int = 600,
  initial_url? : String = "about:blank",
  size_hint? : WindowSizeHint = WindowSizeHint::Unconstrained,
  titlebar_style? : TitlebarStyle = TitlebarStyle::Default,
  browser? : BrowserPolicy = BrowserPolicy::new(),
  bridge? : BridgeConfig,
) -> WindowConfig {
  {
    raw_json: None,
    title,
    width,
    height,
    initial_url,
    size_hint,
    titlebar_style,
    browser,
    bridge,
    framework_titlebar_minimize_label: Some("Minimize"),
    framework_titlebar_maximize_label: Some("Maximize"),
    framework_titlebar_restore_label: Some("Restore"),
    framework_titlebar_close_label: Some("Close"),
  }
}

///|
pub fn WindowConfig::unsafe_from_json(raw_json : String) -> WindowConfig {
  {
    raw_json: Some(raw_json),
    title: "Proton",
    width: 800,
    height: 600,
    initial_url: "about:blank",
    size_hint: WindowSizeHint::Unconstrained,
    titlebar_style: TitlebarStyle::Default,
    browser: BrowserPolicy::new(),
    bridge: None,
    framework_titlebar_minimize_label: None,
    framework_titlebar_maximize_label: None,
    framework_titlebar_restore_label: None,
    framework_titlebar_close_label: None,
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
    raw_json: self.raw_json,
    use_bundled: self.use_bundled,
    headless: self.headless,
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
    remote_debugging_port: self.remote_debugging_port,
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
    raw_json: self.raw_json,
    title: self.title,
    width: self.width,
    height: self.height,
    initial_url: self.initial_url,
    size_hint: self.size_hint,
    titlebar_style: self.titlebar_style,
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
pub fn MenuBar::new(menus~ : Array[Menu]) -> MenuBar {
  { menus: menus.copy() }
}

///|
/// Creates a top-level menu.
pub fn Menu::new(label : String, items~ : Array[MenuItem]) -> Menu {
  { label: Some(label), role: None, items: Some(items.copy()) }
}

///|
/// Creates a standard top-level menu. Omitted items select the role defaults;
/// an explicit item array replaces those defaults exactly.
pub fn Menu::role(
  role : MenuRole,
  label? : String,
  items? : Array[MenuItem],
) -> Menu {
  { label, role: Some(role), items: items.map(items => items.copy()) }
}

///|
/// Creates an app command item. Activating it emits `menu_command`.
pub fn MenuItem::command(
  id : String,
  label : String,
  key? : String,
) -> MenuItem {
  { kind: "command", id: Some(id), label: Some(label), key, role: None }
}

///|
/// Creates a menu separator.
pub fn MenuItem::separator() -> MenuItem {
  { kind: "separator", id: None, label: None, key: None, role: None }
}

///|
/// Creates an item backed by a platform menu role such as `close` or `quit`.
pub fn MenuItem::role(
  role : MenuItemRole,
  label? : String,
  key? : String,
) -> MenuItem {
  { kind: "role", id: None, label, key, role: Some(role) }
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
) -> (String, String?, String?, String?, MenuItemRole?) {
  (self.kind, self.id, self.label, self.key, self.role)
}

///|
pub fn WindowRef::unsafe_from_handle(handle : Int64) -> WindowRef {
  WindowRef::{ handle, }
}

///|
pub fn BridgeConfig::new(
  grants~ : Array[BridgeGrantConfig],
  max_payload_bytes? : Int = 1048576,
) -> BridgeConfig {
  {
    raw_json: None,
    max_payload_bytes,
    grants: grants.map(fn(grant) { grant.copy() }),
  }
}

///|
pub fn BridgeConfig::unsafe_from_json(raw_json : String) -> BridgeConfig {
  { raw_json: Some(raw_json), max_payload_bytes: 1048576, grants: [] }
}

///|
pub fn BridgeGrantConfig::new(
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
pub fn BridgeExtensionConfig::new(
  js_namespace : String,
  apis~ : Array[String],
) -> BridgeExtensionConfig {
  { js_namespace, apis: copy_strings(apis) }
}

///|
pub fn BridgeInitializationUnit::new(
  owner : String,
  name : String,
  source : String,
) -> BridgeInitializationUnit {
  { owner, name, source }
}

///|
fn BridgeInitializationUnit::copy(
  self : BridgeInitializationUnit,
) -> BridgeInitializationUnit {
  { owner: self.owner, name: self.name, source: self.source }
}

///|
fn BridgeExtensionConfig::copy(
  self : BridgeExtensionConfig,
) -> BridgeExtensionConfig {
  { js_namespace: self.js_namespace, apis: copy_strings(self.apis) }
}

///|
fn BridgeGrantConfig::copy(self : BridgeGrantConfig) -> BridgeGrantConfig {
  BridgeGrantConfig::new(
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
fn set_optional_string_field(
  fields : Map[String, Json],
  name : String,
  value : String?,
) -> Unit {
  match value {
    Some(text) => fields.set(name, Json(text))
    None => ()
  }
}

///|
pub fn RuntimeConfig::to_json_string(self : RuntimeConfig) -> String {
  match self.raw_json {
    Some(raw) => raw
    None => {
      let fields : Map[String, Json] = {
        "abi_version": Json::number(1.0, repr="1"),
        "remote_debugging_port": Json::number(
          self.remote_debugging_port.to_double(),
          repr=self.remote_debugging_port.to_string(),
        ),
      }
      if self.use_bundled {
        fields.set("use_bundled", Json(true))
      }
      if self.headless {
        fields.set("headless", Json(true))
      }
      fields.set(
        "persist_session_cookies",
        Json::boolean(self.persist_session_cookies),
      )
      set_optional_string_field(fields, "runtime_root", self.runtime_root)
      set_optional_string_field(fields, "helper_path", self.helper_path)
      set_optional_string_field(fields, "resources_dir", self.resources_dir)
      set_optional_string_field(fields, "locales_dir", self.locales_dir)
      set_optional_string_field(fields, "cache_dir", self.cache_dir)
      set_optional_string_field(fields, "locale", self.locale)
      if !self.accept_languages.is_empty() {
        fields.set(
          "accept_languages",
          Json::array(self.accept_languages.map(language => Json(language))),
        )
      }
      set_optional_string_field(
        fields,
        "framework_dialog_ok_label",
        self.framework_dialog_ok_label,
      )
      set_optional_string_field(
        fields,
        "framework_dialog_cancel_label",
        self.framework_dialog_cancel_label,
      )
      Json::object(fields).stringify()
    }
  }
}

///|
fn BrowserPolicyMode::to_json_string(self : BrowserPolicyMode) -> String {
  match self {
    Allow => "allow"
    Deny => "deny"
    Ask => "ask"
  }
}

///|
fn BrowserPolicy::to_json(self : BrowserPolicy) -> Json {
  {
    "navigation": self.navigation.to_json_string(),
    "popup": self.popup.to_json_string(),
    "download": self.download.to_json_string(),
    "certificate": self.certificate.to_json_string(),
    "media": self.media.to_json_string(),
    "devtools": self.devtools,
  }
}

///|
pub fn WindowConfig::to_json_string(self : WindowConfig) -> String {
  match self.raw_json {
    Some(raw) => raw
    None => {
      let fields : Map[String, Json] = {
        "abi_version": Json::number(1.0, repr="1"),
        "title": self.title,
        "width": Json::number(
          self.width.to_double(),
          repr=self.width.to_string(),
        ),
        "height": Json::number(
          self.height.to_double(),
          repr=self.height.to_string(),
        ),
        "initial_url": self.initial_url,
      }
      match self.titlebar_style {
        TitlebarStyle::Default => ()
        TitlebarStyle::Overlay =>
          if titlebar_overlay_config_supported() {
            fields["titlebar_style"] = Json("overlay")
          }
      }
      if window_size_hint_config_supported() {
        match self.size_hint {
          WindowSizeHint::Unconstrained => ()
          WindowSizeHint::Fixed => fields["size_hint"] = Json("fixed")
          WindowSizeHint::Min => fields["size_hint"] = Json("min")
          WindowSizeHint::Max => fields["size_hint"] = Json("max")
        }
      }
      match self.bridge {
        Some(bridge) => fields.set("bridge", bridge.to_json())
        None => ()
      }
      fields.set("browser", self.browser.to_json())
      set_optional_string_field(
        fields,
        "framework_titlebar_minimize_label",
        self.framework_titlebar_minimize_label,
      )
      set_optional_string_field(
        fields,
        "framework_titlebar_maximize_label",
        self.framework_titlebar_maximize_label,
      )
      set_optional_string_field(
        fields,
        "framework_titlebar_restore_label",
        self.framework_titlebar_restore_label,
      )
      set_optional_string_field(
        fields,
        "framework_titlebar_close_label",
        self.framework_titlebar_close_label,
      )
      Json::object(fields).stringify()
    }
  }
}

///|
fn MenuItem::to_json(self : MenuItem) -> Json {
  let fields : Map[String, Json] = { "kind": self.kind }
  set_optional_string_field(fields, "id", self.id)
  set_optional_string_field(fields, "label", self.label)
  set_optional_string_field(fields, "key", self.key)
  match self.role {
    Some(role) => fields.set("role", Json(role.to_json_string()))
    None => ()
  }
  Json::object(fields)
}

///|
fn Menu::to_json(self : Menu) -> Json {
  let fields : Map[String, Json] = Map([])
  set_optional_string_field(fields, "label", self.label)
  match self.role {
    Some(role) => fields.set("role", Json(role.to_json_string()))
    None => ()
  }
  match self.items {
    Some(items) =>
      fields.set("items", Json::array(items.map(item => item.to_json())))
    None => ()
  }
  Json::object(fields)
}

///|
fn MenuRole::to_json_string(self : MenuRole) -> String {
  match self {
    Application => "application"
    File => "file"
    Edit => "edit"
    View => "view"
    Window => "window"
    Help => "help"
  }
}

///|
fn MenuItemRole::to_json_string(self : MenuItemRole) -> String {
  match self {
    Quit => "quit"
    Hide => "hide"
    HideOthers => "hide_others"
    ShowAll => "show_all"
    Close => "close"
    Minimize => "minimize"
    Zoom => "zoom"
    Undo => "undo"
    Redo => "redo"
    Cut => "cut"
    Copy => "copy"
    Paste => "paste"
    SelectAll => "select_all"
  }
}

///|
/// Encodes this menu bar for the native ABI.
pub fn MenuBar::to_json_string(self : MenuBar) -> String {
  let json : Json = {
    "abi_version": Json::number(1.0, repr="1"),
    "menus": self.menus.map(fn(menu) { menu.to_json() }),
  }
  json.stringify()
}

///|
fn BridgeConfig::to_json(self : BridgeConfig) -> Json {
  match self.raw_json {
    Some(raw) => @json.parse(raw) catch { _ => null }
    None => {
      let fields : Map[String, Json] = {
        "abi_version": Json::number(2.0, repr="2"),
        "namespace": "__MoonBit__",
        "grants": self.grants.map(fn(grant) -> Json {
          {
            "source_origin": grant.source_origin,
            "ops": grant.ops.map(fn(name) -> Json { { "name": name } }),
            "extensions": grant.extensions.map(fn(extension) -> Json {
              { "namespace": extension.js_namespace, "apis": extension.apis }
            }),
            "initialization_units": grant.initialization_units.map(fn(
              unit,
            ) -> Json {
              { "owner": unit.owner, "name": unit.name, "source": unit.source }
            }),
          }
        }),
        "max_payload_bytes": Json::number(
          self.max_payload_bytes.to_double(),
          repr=self.max_payload_bytes.to_string(),
        ),
      }
      Json::object(fields)
    }
  }
}

///|
pub fn BridgeConfig::to_json_string(self : BridgeConfig) -> String {
  self.to_json().stringify()
}

///|
pub fn BridgeResponse::to_json_string(self : BridgeResponse) -> String {
  match self {
    Ok(request_id~, payload~) => {
      let response : Json = {
        "abi_version": Json::number(1.0, repr="1"),
        "request_id": Json::number(
          request_id.to_double(),
          repr=request_id.to_string(),
        ),
        "ok": true,
        "payload": payload,
      }
      response.stringify()
    }
    Err(request_id~, code~, message~) => {
      let response : Json = {
        "abi_version": Json::number(1.0, repr="1"),
        "request_id": Json::number(
          request_id.to_double(),
          repr=request_id.to_string(),
        ),
        "ok": false,
        "error": { "code": code, "message": message },
      }
      response.stringify()
    }
  }
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
  mut handle : Int64
  mut lifecycle : ViewLifecycleState
}

///|
/// A borrowed view handle for APIs that must not destroy the view.
struct ViewRef {
  handle : Int64
} derive(Debug, Eq)

///|
pub extend ViewRef with Eq::{not_equal, equal}

///|
pub extend ViewRef with Debug::{to_repr}

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
} derive(Debug, Eq, FromJson)

///|
pub extend ViewState with Eq::{not_equal, equal}

///|
pub extend ViewState with Debug::{to_repr}

///|
pub extend ViewState with FromJson::{from_json}

///|
/// Native configuration for one web contents view. `width` and `height` are
/// required because the native browser needs an initial rectangle; `x`/`y`
/// default to `0`, `visible` to `true`, `z_order` to `0`, and `initial_url`
/// to `about:blank`. Views stack above the window's main browser, ordered by
/// ascending `z_order`.
struct ViewConfig {
  raw_json : String?
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
pub fn ViewConfig::new(
  width~ : Int,
  height~ : Int,
  x? : Int = 0,
  y? : Int = 0,
  visible? : Bool = true,
  z_order? : Int = 0,
  initial_url? : String = "about:blank",
  background_color? : String,
) -> ViewConfig {
  {
    raw_json: None,
    x,
    y,
    width,
    height,
    visible,
    z_order,
    initial_url,
    background_color,
  }
}

///|
/// Creates a view config from unchecked native ABI JSON.
pub fn ViewConfig::unsafe_from_json(raw_json : String) -> ViewConfig {
  {
    raw_json: Some(raw_json),
    x: 0,
    y: 0,
    width: 0,
    height: 0,
    visible: true,
    z_order: 0,
    initial_url: "about:blank",
    background_color: None,
  }
}

///|
pub fn ViewConfig::to_json_string(self : ViewConfig) -> String {
  match self.raw_json {
    Some(raw) => raw
    None => {
      let fields : Map[String, Json] = {
        "abi_version": Json::number(1.0, repr="1"),
        "x": Json::number(self.x.to_double(), repr=self.x.to_string()),
        "y": Json::number(self.y.to_double(), repr=self.y.to_string()),
        "width": Json::number(
          self.width.to_double(),
          repr=self.width.to_string(),
        ),
        "height": Json::number(
          self.height.to_double(),
          repr=self.height.to_string(),
        ),
        "visible": self.visible,
        "z_order": Json::number(
          self.z_order.to_double(),
          repr=self.z_order.to_string(),
        ),
        "initial_url": self.initial_url,
      }
      match self.background_color {
        Some(color) => fields.set("background_color", Json(color))
        None => ()
      }
      Json::object(fields).stringify()
    }
  }
}

///|
/// Returns true when the loaded native runtime supports web contents views.
pub fn web_contents_view_supported() -> Bool {
  let info = cached_runtime_info() catch { _ => return false }
  info.features.contains("web_contents_view")
}

///|
pub fn ViewRef::unsafe_from_handle(handle : Int64) -> ViewRef {
  ViewRef::{ handle, }
}
