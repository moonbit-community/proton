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
impl Show for NativeError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
pub(all) enum ProcessResult {
  MainProcess
  SubprocessHandled(Int)
} derive(Debug, Eq)

///|
pub(all) struct RuntimeInfo {
  abi_version : Int
  runtime_available : Bool
  build_mode : String
  platform : String
  features : Array[String]
} derive(Debug, Eq, FromJson)

///|
pub(all) struct RuntimeWaitReady {
  mask : Int
} derive(Debug, Eq)

///|
struct RuntimeEvent {
  event_type : String
  window : Int64?
  menu_command_id : String?
  revision : Int64?
} derive(Debug, Eq)

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
pub(all) struct BridgeRequest {
  request_id : Int64
  window : Int64
  op : String
  payload : Json
  page_instance : String?
} derive(Debug)

///|
pub(all) enum BridgeResponse {
  Ok(request_id~ : Int64, payload~ : Json)
  Err(request_id~ : Int64, code~ : String, message~ : String)
} derive(Debug)

///|
pub(all) enum DialogLevel {
  Info
  Warning
  Error
} derive(Debug, Eq)

///|
pub(all) enum DialogPollResult {
  Pending
  Ready(String)
} derive(Debug, Eq)

///|
/// A native notification activation, optionally carrying its application
/// payload.
pub(all) struct NativeNotificationClick {
  payload : String?
} derive(Debug, Eq)

///|
/// An application-level native menu bar.
struct MenuBar {
  raw_json : String?
  menus : Array[Menu]
} derive(Debug, Eq)

///|
/// A top-level native menu and its items.
struct Menu {
  label : String
  items : Array[MenuItem]
} derive(Debug, Eq)

///|
/// A command, separator, or platform role in a native menu.
struct MenuItem {
  kind : String
  id : String?
  label : String?
  key : String?
  role : String?
} derive(Debug, Eq)

///|
pub(all) struct BridgeConfig {
  raw_json : String?
  ops : Array[String]
  max_payload_bytes : Int
  request_timeout_ms : Int
  dev_origins : Array[String]
  extensions : Array[BridgeExtensionConfig]
  initialization_units : Array[BridgeInitializationUnit]
} derive(Debug, Eq)

///|
/// One JavaScript namespace installed by the renderer bootstrap.
pub(all) struct BridgeExtensionConfig {
  js_namespace : String
  apis : Array[String]
} derive(Debug, Eq)

///|
/// One ordered JavaScript initialization unit owned by an extension.
pub(all) struct BridgeInitializationUnit {
  owner : String
  name : String
  source : String
} derive(Debug, Eq)

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
pub fn RuntimeEvent::is_window_created(self : RuntimeEvent) -> Bool {
  self.event_type == "window_created"
}

///|
pub fn RuntimeEvent::is_window_closed(self : RuntimeEvent) -> Bool {
  self.event_type == "window_closed"
}

///|
pub fn RuntimeEvent::is_bridge_lifecycle_changed(self : RuntimeEvent) -> Bool {
  self.event_type == "bridge_lifecycle_changed"
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
struct Runtime {
  mut handle : Int64
}

///|
struct Window {
  mut handle : Int64
}

///|
struct WindowRef {
  handle : Int64
} derive(Debug, Eq)

///|
pub(all) enum TitlebarStyle {
  Default
  Overlay
} derive(Debug, Eq)

///|
fn titlebar_overlay_config_supported() -> Bool {
  let info = runtime_info() catch { _ => return false }
  info.features.contains("titlebar_overlay")
}

///|
struct RuntimeConfig {
  raw_json : String?
  use_bundled : Bool
  runtime_root : String?
  helper_path : String?
  resources_dir : String?
  locales_dir : String?
  cache_dir : String?
  remote_debugging_port : Int
} derive(Debug, Eq)

///|
struct WindowConfig {
  raw_json : String?
  title : String
  width : Int
  height : Int
  initial_url : String
  titlebar_style : TitlebarStyle
  bridge : BridgeConfig?
} derive(Debug, Eq)

///|
pub fn RuntimeConfig::new(
  runtime_root? : String,
  helper_path? : String,
  resources_dir? : String,
  locales_dir? : String,
  cache_dir? : String,
  remote_debugging_port? : Int = 0,
) -> RuntimeConfig {
  {
    raw_json: None,
    use_bundled: false,
    runtime_root,
    helper_path,
    resources_dir,
    locales_dir,
    cache_dir,
    remote_debugging_port,
  }
}

///|
pub fn RuntimeConfig::unsafe_from_json(raw_json : String) -> RuntimeConfig {
  {
    raw_json: Some(raw_json),
    use_bundled: false,
    runtime_root: None,
    helper_path: None,
    resources_dir: None,
    locales_dir: None,
    cache_dir: None,
    remote_debugging_port: 0,
  }
}

///|
/// `helper_path`, when set, overrides the subprocess executable the bundled
/// runtime launches. On macOS the helper must run from a nested `.app` so
/// Chromium's outer-bundle walk yields the same base bundle id as the browser;
/// otherwise the MachPort rendezvous service names mismatch and every child
/// process terminates. Framework and resource discovery still run relative to
/// the loaded `libproton`, so only the helper needs an explicit path.
pub fn RuntimeConfig::bundled(
  helper_path? : String,
  cache_dir? : String,
  remote_debugging_port? : Int = 0,
) -> RuntimeConfig {
  {
    raw_json: None,
    use_bundled: true,
    runtime_root: None,
    helper_path,
    resources_dir: None,
    locales_dir: None,
    cache_dir,
    remote_debugging_port,
  }
}

///|
pub fn WindowConfig::new(
  title? : String = "Proton",
  width? : Int = 800,
  height? : Int = 600,
  initial_url? : String = "about:blank",
  titlebar_style? : TitlebarStyle = TitlebarStyle::Default,
  bridge? : BridgeConfig,
) -> WindowConfig {
  { raw_json: None, title, width, height, initial_url, titlebar_style, bridge }
}

///|
pub fn WindowConfig::unsafe_from_json(raw_json : String) -> WindowConfig {
  {
    raw_json: Some(raw_json),
    title: "Proton",
    width: 800,
    height: 600,
    initial_url: "about:blank",
    titlebar_style: TitlebarStyle::Default,
    bridge: None,
  }
}

///|
/// Creates an application-level menu bar.
pub fn MenuBar::new(menus~ : Array[Menu]) -> MenuBar {
  { raw_json: None, menus }
}

///|
/// Creates a menu bar from unchecked native ABI JSON.
pub fn MenuBar::unsafe_from_json(raw_json : String) -> MenuBar {
  { raw_json: Some(raw_json), menus: [] }
}

///|
/// Creates a top-level menu.
pub fn Menu::new(label : String, items~ : Array[MenuItem]) -> Menu {
  { label, items }
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
  role : String,
  label? : String,
  key? : String,
) -> MenuItem {
  { kind: "role", id: None, label, key, role: Some(role) }
}

///|
pub fn WindowRef::unsafe_from_handle(handle : Int64) -> WindowRef {
  WindowRef::{ handle, }
}

///|
pub fn BridgeConfig::new(
  ops~ : Array[String],
  max_payload_bytes? : Int = 1048576,
  request_timeout_ms? : Int = 30000,
  dev_origins? : Array[String] = [],
  extensions? : Array[BridgeExtensionConfig] = [],
  initialization_units? : Array[BridgeInitializationUnit] = [],
) -> BridgeConfig {
  {
    raw_json: None,
    ops,
    max_payload_bytes,
    request_timeout_ms,
    dev_origins: copy_strings(dev_origins),
    extensions: extensions.map(fn(extension) { extension.copy() }),
    initialization_units: initialization_units.map(fn(unit) { unit.copy() }),
  }
}

///|
pub fn BridgeConfig::unsafe_from_json(raw_json : String) -> BridgeConfig {
  {
    raw_json: Some(raw_json),
    ops: [],
    max_payload_bytes: 1048576,
    request_timeout_ms: 30000,
    dev_origins: [],
    extensions: [],
    initialization_units: [],
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
    Some(text) => fields.set(name, Json::string(text))
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
        fields.set("use_bundled", Json::boolean(true))
      }
      set_optional_string_field(fields, "runtime_root", self.runtime_root)
      set_optional_string_field(fields, "helper_path", self.helper_path)
      set_optional_string_field(fields, "resources_dir", self.resources_dir)
      set_optional_string_field(fields, "locales_dir", self.locales_dir)
      set_optional_string_field(fields, "cache_dir", self.cache_dir)
      Json::object(fields).stringify()
    }
  }
}

///|
pub fn WindowConfig::to_json_string(self : WindowConfig) -> String {
  match self.raw_json {
    Some(raw) => raw
    None => {
      let fields : Map[String, Json] = {
        "abi_version": Json::number(1.0, repr="1"),
        "title": Json::string(self.title),
        "width": Json::number(
          self.width.to_double(),
          repr=self.width.to_string(),
        ),
        "height": Json::number(
          self.height.to_double(),
          repr=self.height.to_string(),
        ),
        "initial_url": Json::string(self.initial_url),
      }
      match self.titlebar_style {
        TitlebarStyle::Default => ()
        TitlebarStyle::Overlay =>
          if titlebar_overlay_config_supported() {
            fields["titlebar_style"] = Json::string("overlay")
          }
      }
      match self.bridge {
        Some(bridge) => fields.set("bridge", bridge.to_json())
        None => ()
      }
      Json::object(fields).stringify()
    }
  }
}

///|
fn MenuItem::to_json(self : MenuItem) -> Json {
  let fields : Map[String, Json] = { "kind": Json::string(self.kind) }
  set_optional_string_field(fields, "id", self.id)
  set_optional_string_field(fields, "label", self.label)
  set_optional_string_field(fields, "key", self.key)
  set_optional_string_field(fields, "role", self.role)
  Json::object(fields)
}

///|
fn Menu::to_json(self : Menu) -> Json {
  Json::object({
    "label": Json::string(self.label),
    "items": Json::array(self.items.map(fn(item) { item.to_json() })),
  })
}

///|
/// Encodes this menu bar for the native ABI.
pub fn MenuBar::to_json_string(self : MenuBar) -> String {
  match self.raw_json {
    Some(raw) => raw
    None =>
      Json::object({
        "abi_version": Json::number(1.0, repr="1"),
        "menus": Json::array(self.menus.map(fn(menu) { menu.to_json() })),
      }).stringify()
  }
}

///|
fn BridgeConfig::to_json(self : BridgeConfig) -> Json {
  match self.raw_json {
    Some(raw) => @json.parse(raw) catch { _ => Json::null() }
    None => {
      let ops_json = self.ops.map(fn(name) {
        Json::object({ "name": Json::string(name) })
      })
      let origin_policy = if self.dev_origins.length() == 0 {
        Json::object({ "mode": Json::string("app_only") })
      } else {
        Json::object({
          "mode": Json::string("app_and_dev_origins"),
          "dev_origins": Json::array(
            self.dev_origins.map(fn(origin) { Json::string(origin) }),
          ),
        })
      }
      let fields : Map[String, Json] = {
        "abi_version": Json::number(1.0, repr="1"),
        "namespace": Json::string("__MoonBit__"),
        "origin_policy": origin_policy,
        "ops": Json::array(ops_json),
        "max_payload_bytes": Json::number(
          self.max_payload_bytes.to_double(),
          repr=self.max_payload_bytes.to_string(),
        ),
        "request_timeout_ms": Json::number(
          self.request_timeout_ms.to_double(),
          repr=self.request_timeout_ms.to_string(),
        ),
        "extensions": Json::array(
          self.extensions.map(fn(extension) {
            Json::object({
              "namespace": Json::string(extension.js_namespace),
              "apis": Json::array(
                extension.apis.map(fn(api) { Json::string(api) }),
              ),
            })
          }),
        ),
      }
      fields.set(
        "initialization_units",
        Json::array(
          self.initialization_units.map(fn(unit) {
            Json::object({
              "owner": Json::string(unit.owner),
              "name": Json::string(unit.name),
              "source": Json::string(unit.source),
            })
          }),
        ),
      )
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
    Ok(request_id~, payload~) =>
      Json::object({
        "abi_version": Json::number(1.0, repr="1"),
        "request_id": Json::number(
          request_id.to_double(),
          repr=request_id.to_string(),
        ),
        "ok": Json::boolean(true),
        "payload": payload,
      }).stringify()
    Err(request_id~, code~, message~) =>
      Json::object({
        "abi_version": Json::number(1.0, repr="1"),
        "request_id": Json::number(
          request_id.to_double(),
          repr=request_id.to_string(),
        ),
        "ok": Json::boolean(false),
        "error": Json::object({
          "code": Json::string(code),
          "message": Json::string(message),
        }),
      }).stringify()
  }
}
