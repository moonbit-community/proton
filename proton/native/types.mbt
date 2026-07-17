///|
pub(all) struct NativeError {
  status : Int
  message : String
} derive(Debug, Eq)

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
  has_window : Bool
  payload : String?
} derive(Debug, Eq)

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
struct MenuBar {
  raw_json : String?
  menus : Array[Menu]
} derive(Debug, Eq)

///|
struct Menu {
  label : String
  items : Array[MenuItem]
} derive(Debug, Eq)

///|
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
  dev_bootstrap_script : String?
} derive(Debug, Eq)

///|
pub fn RuntimeEvent::event_type(self : RuntimeEvent) -> String {
  self.event_type
}

///|
pub fn RuntimeEvent::has_window(self : RuntimeEvent) -> Bool {
  self.has_window
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
/// The payload of a clicked system notification (the string given to
/// `post_notification`), or `None` for every other event kind.
pub fn RuntimeEvent::notification_click_payload(self : RuntimeEvent) -> String? {
  if self.event_type == "notification_clicked" {
    self.payload
  } else {
    None
  }
}

///|
/// The command id for an app-menu command item click, or `None` for every
/// other event kind.
pub fn RuntimeEvent::menu_command_id(self : RuntimeEvent) -> String? {
  if self.event_type == "menu_command" {
    self.payload
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
) -> WindowConfig {
  { raw_json: None, title, width, height, initial_url }
}

///|
pub fn WindowConfig::unsafe_from_json(raw_json : String) -> WindowConfig {
  {
    raw_json: Some(raw_json),
    title: "Proton",
    width: 800,
    height: 600,
    initial_url: "about:blank",
  }
}

///|
pub fn MenuBar::new(menus~ : Array[Menu]) -> MenuBar {
  { raw_json: None, menus }
}

///|
pub fn MenuBar::unsafe_from_json(raw_json : String) -> MenuBar {
  { raw_json: Some(raw_json), menus: [] }
}

///|
pub fn Menu::new(label : String, items~ : Array[MenuItem]) -> Menu {
  { label, items }
}

///|
pub fn MenuItem::command(
  id : String,
  label : String,
  key? : String,
) -> MenuItem {
  { kind: "command", id: Some(id), label: Some(label), key, role: None }
}

///|
pub fn MenuItem::separator() -> MenuItem {
  { kind: "separator", id: None, label: None, key: None, role: None }
}

///|
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
  dev_bootstrap_script? : String? = None,
) -> BridgeConfig {
  {
    raw_json: None,
    ops,
    max_payload_bytes,
    request_timeout_ms,
    dev_origins: copy_strings(dev_origins),
    dev_bootstrap_script,
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
    dev_bootstrap_script: None,
  }
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
    None =>
      Json::object({
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
      }).stringify()
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
pub fn BridgeConfig::to_json_string(self : BridgeConfig) -> String {
  match self.raw_json {
    Some(raw) => raw
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
      }
      set_optional_string_field(
        fields,
        "dev_bootstrap_script",
        self.dev_bootstrap_script,
      )
      Json::object(fields).stringify()
    }
  }
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
