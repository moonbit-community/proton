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
  /// Set on `dialog_completed` events only.
  dialog_request : UInt64?
  dialog_accepted : Bool
  dialog_path : String?
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
pub(all) struct BridgeConfig {
  raw_json : String?
  ops : Array[String]
  max_payload_bytes : Int
  request_timeout_ms : Int
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
pub fn RuntimeEvent::is_dialog_completed(self : RuntimeEvent) -> Bool {
  self.event_type == "dialog_completed"
}

///|
/// The async dialog request this event settles; None on other event types.
pub fn RuntimeEvent::dialog_request(self : RuntimeEvent) -> UInt64? {
  self.dialog_request
}

///|
/// Whether the user confirmed the dialog (as opposed to cancelling it).
pub fn RuntimeEvent::dialog_accepted(self : RuntimeEvent) -> Bool {
  self.dialog_accepted
}

///|
/// The picked path of an accepted `dialog_completed` event.
pub fn RuntimeEvent::dialog_path(self : RuntimeEvent) -> String? {
  self.dialog_path
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
pub fn WindowRef::unsafe_from_handle(handle : Int64) -> WindowRef {
  WindowRef::{ handle, }
}

///|
pub fn BridgeConfig::new(
  ops~ : Array[String],
  max_payload_bytes? : Int = 1048576,
  request_timeout_ms? : Int = 30000,
) -> BridgeConfig {
  { raw_json: None, ops, max_payload_bytes, request_timeout_ms }
}

///|
pub fn BridgeConfig::unsafe_from_json(raw_json : String) -> BridgeConfig {
  {
    raw_json: Some(raw_json),
    ops: [],
    max_payload_bytes: 1048576,
    request_timeout_ms: 30000,
  }
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
pub fn BridgeConfig::to_json_string(self : BridgeConfig) -> String {
  match self.raw_json {
    Some(raw) => raw
    None => {
      let ops_json = self.ops.map(fn(name) {
        Json::object({ "name": Json::string(name) })
      })
      Json::object({
        "abi_version": Json::number(1.0, repr="1"),
        "namespace": Json::string("__MoonBit__"),
        "origin_policy": Json::object({ "mode": Json::string("app_only") }),
        "ops": Json::array(ops_json),
        "max_payload_bytes": Json::number(
          self.max_payload_bytes.to_double(),
          repr=self.max_payload_bytes.to_string(),
        ),
        "request_timeout_ms": Json::number(
          self.request_timeout_ms.to_double(),
          repr=self.request_timeout_ms.to_string(),
        ),
      }).stringify()
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
