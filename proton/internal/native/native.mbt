///|
pub fn abi_version() -> Int {
  @native_ffi.proton_abi_version_ffi()
}

///|
fn runtime_platform_id() -> String raise NativeError {
  require_native_text("runtime platform id", (buffer, buffer_len, required) => {
    @native_ffi.proton_runtime_platform_id_ffi(buffer, buffer_len, required)
  })
}

///|
pub fn runtime_info() -> RuntimeInfo raise NativeError {
  let platform_id = runtime_platform_id()
  let platform = if platform_id.has_prefix("win32-") {
    "windows"
  } else if platform_id.has_prefix("darwin-") {
    "macos"
  } else {
    "linux"
  }
  RuntimeInfo::{
    platform,
    platform_id,
    features: [
      "event_polling", "bridge_events", "bridge_permission_grants", "titlebar_overlay",
      "headless_osr", "window_size_hints", "window_session", "browser_session", "app_single_instance",
      "web_contents_view", "native_image",
    ],
  }
}

///|
/// Returns the operating system's preferred language tags in preference order.
///
/// Platform adapters may return platform-native locale syntax. The public
/// facade owns validation and canonicalization into `Locale` values.
pub fn system_preferred_language_tags() -> Array[String] raise NativeError {
  let text = require_native_text("system preferred languages", (
    buffer,
    buffer_len,
    required,
  ) => {
    @native_ffi.proton_system_preferred_languages_json_ffi(
      buffer, buffer_len, required,
    )
  })
  @json.from_json(decode_native_json(text, "system preferred languages")) catch {
    error =>
      raise InvalidPayload(
        context="system preferred languages",
        message="expected string array: " + error.to_string(),
      )
  }
}

///|
/// Enumerates all connected displays.
///
/// Returns an array of `ScreenInfo` describing each monitor's bounds, work
/// area, scale factor, and primary flag. The first entry is always the
/// primary display. Raises `UnsupportedNativeFeature` when the native
/// engine is not available.
pub fn screens() -> Array[ScreenInfo] raise NativeError {
  let fields = FixedArray::make(
    proton_max_screens * proton_screen_field_count,
    0,
  )
  let count = Ref(0)
  check_status(
    @native_ffi.proton_screen_enumerate_ffi(fields, fields.length(), count),
  )
  let screens = []
  for index in 0..<count.val {
    let offset = index * proton_screen_field_count
    screens.push({
      id: fields[offset],
      x: fields[offset + 1],
      y: fields[offset + 2],
      width: fields[offset + 3],
      height: fields[offset + 4],
      work_x: fields[offset + 5],
      work_y: fields[offset + 6],
      work_width: fields[offset + 7],
      work_height: fields[offset + 8],
      scale_factor_percent: fields[offset + 9],
      is_primary: fields[offset + 10] != 0,
    })
  }
  screens
}

///|
pub fn AppActivation::AppActivation(
  urls? : Array[String] = [],
  files? : Array[String] = [],
  reopen? : Bool = false,
) -> AppActivation {
  AppActivation::{
    abi_version: 1,
    urls: urls.copy(),
    files: files.copy(),
    reopen,
  }
}

///|
/// Claims one operating-system application identity. A secondary process
/// forwards its activation before returning `Forwarded`.
pub fn AppInstance::acquire(
  identifier : String,
  activation : AppActivation,
) -> AppInstanceAcquire raise NativeError {
  if identifier.trim().to_owned() == "" {
    raise invalid_argument("app instance identifier must not be empty")
  }
  let out_instance = Ref(proton_invalid_handle)
  let out_primary = Ref(0)
  let status = @native_ffi.proton_app_instance_acquire_ffi(
    @ffi.to_cstr(identifier),
    @ffi.to_cstr(activation.to_json().stringify()),
    out_instance,
    out_primary,
  )
  if status < 0 {
    raise native_error(status)
  } else if out_primary.val == 0 {
    AppInstanceAcquire::Forwarded
  } else if out_instance.val == proton_invalid_handle {
    raise InvalidPayload(
      context="app instance",
      message="primary acquisition returned an invalid handle",
    )
  } else {
    AppInstanceAcquire::Primary(AppInstance::{
      handle: out_instance.val,
      destroyed: false,
    })
  }
}

///|
/// Attaches the primary instance listener to a runtime's existing wake source.
pub fn AppInstance::attach_runtime(
  self : AppInstance,
  runtime : Runtime,
) -> Unit raise NativeError {
  if self.destroyed {
    raise invalid_argument("app instance is destroyed")
  }
  check_status(
    @native_ffi.proton_app_instance_attach_runtime_ffi(
      self.handle,
      runtime.active_handle(),
    ),
  )
}

///|
pub fn AppInstance::destroy(self : AppInstance) -> Unit raise NativeError {
  if self.destroyed {
    return
  }
  check_status(@native_ffi.proton_app_instance_destroy_ffi(self.handle))
  self.handle = proton_invalid_handle
  self.destroyed = true
}

///|
pub fn last_error_message() -> String {
  let required = @native_ffi.proton_last_error_message_ffi(
    FixedArray::make(1, b'\x00'),
    0,
  )
  if required <= 0 {
    return ""
  }
  let buffer = FixedArray::make(required + 1, b'\x00')
  let _ = @native_ffi.proton_last_error_message_ffi(buffer, buffer.length())
  @ffi.from_cstr(Bytes::from_array(buffer))
}

///|
fn native_error(status : Int) -> NativeError {
  Status(status~, message=last_error_message())
}

///|
fn check_status(status : Int) -> Unit raise NativeError {
  if status < 0 {
    raise native_error(status)
  }
}

///|
fn invalid_argument(message : String) -> NativeError {
  InvalidArgument(message~)
}

///|
fn validate_window_config(config : WindowConfig) -> Unit raise NativeError {
  if config.width <= 0 || config.height <= 0 {
    raise invalid_argument("width and height must be positive")
  }
  if config.browser.popup is BrowserPolicyMode::Allow ||
    config.browser.certificate is BrowserPolicyMode::Allow ||
    config.browser.media is BrowserPolicyMode::Allow {
    raise invalid_argument(
      "popup, certificate, and media policies cannot allow without review",
    )
  }
}

///|
fn window_size_hint_code(value : WindowSizeHint) -> Int {
  match value {
    Unconstrained => 0
    Fixed => 1
    Min => 2
    Max => 3
  }
}

///|
fn validate_size_constraint(
  width : Int,
  height : Int,
  name : String,
) -> Unit raise NativeError {
  if width == 0 && height == 0 {
    return
  }
  if width <= 0 || height <= 0 {
    raise invalid_argument(
      name + " size must use two positive dimensions or (0, 0) to clear",
    )
  }
}

///|
fn browser_policy_code(value : BrowserPolicyMode) -> Int {
  match value {
    Allow => 0
    Deny => 1
    Ask => 2
  }
}

///|
fn decode_native_json(text : String, label : String) -> Json raise NativeError {
  @json.parse(text) catch {
    error =>
      raise InvalidPayload(
        context=label + " JSON",
        message="invalid JSON: " + error.to_string(),
      )
  }
}

///|
fn decode_string_json(json : Json, label : String) -> String raise NativeError {
  @json.from_json(json) catch {
    error =>
      raise InvalidPayload(
        context=label,
        message="expected string: " + error.to_string(),
      )
  }
}

///|
/// Rejects payloads whose `abi_version` does not match the schema version
/// this binding implements.
fn expect_abi_version(found : Int, context : String) -> Unit raise NativeError {
  if found != 1 {
    raise InvalidPayload(
      context~,
      message="unsupported abi_version " + found.to_string() + ", expected 1",
    )
  }
}

///|
/// Validates an optional `abi_version` field: absent is accepted (older
/// runtimes do not emit one), but a present field must be the number 1.
fn decode_optional_abi_version(
  object : Map[String, Json],
  context : String,
) -> Unit raise NativeError {
  match object {
    { "abi_version"? : None, .. } => ()
    { "abi_version": Number(version, ..), .. } =>
      expect_abi_version(version.to_int(), context)
    _ => raise InvalidPayload(context~, message="expected number abi_version")
  }
}

///|
fn runtime_event_missing(event_type : String, field : String) -> NativeError {
  InvalidPayload(
    context="runtime event " + event_type,
    message="missing " + field,
  )
}

///|
fn decode_int64_json(json : Json, label : String) -> Int64 raise NativeError {
  @json.from_json(json) catch {
    error =>
      raise InvalidPayload(
        context=label,
        message="expected int64: " + error.to_string(),
      )
  }
}

///|
fn decode_bridge_request_json(text : String) -> BridgeRequest raise NativeError {
  let json = decode_native_json(text, "bridge request")
  let object = match json {
    Object(object) => object
    _ =>
      raise InvalidPayload(context="bridge request", message="expected object")
  }
  decode_optional_abi_version(object, "bridge request")
  guard object is { "request_id": request_id_json, .. } else {
    raise InvalidPayload(context="bridge request", message="missing request_id")
  }
  guard object is { "window": window_json, .. } else {
    raise InvalidPayload(context="bridge request", message="missing window")
  }
  guard object is { "op": op_json, .. } else {
    raise InvalidPayload(context="bridge request", message="missing op")
  }
  guard object
    is {
      "payload"? : payload_json,
      "page_instance"? : page_instance_json,
      "source_origin"? : source_origin_json,
      ..
    }
  let payload = payload_json.unwrap_or(Json::empty_object())
  let page_instance = match page_instance_json {
    Some(String(value)) => Some(value)
    _ => None
  }
  let source_origin = match source_origin_json {
    Some(value) => decode_string_json(value, "bridge request source_origin")
    None =>
      raise InvalidPayload(
        context="bridge request",
        message="missing source_origin",
      )
  }
  let request_id = decode_int64_json(request_id_json, "bridge request_id")
  let window = decode_int64_json(window_json, "bridge request window")
  let op = decode_string_json(op_json, "bridge request op")
  BridgeRequest::{
    request_id,
    window,
    op,
    payload,
    page_instance,
    source_origin,
  }
}

///|
fn runtime_config_bool(value : Bool) -> Int {
  if value {
    1
  } else {
    0
  }
}

///|
fn runtime_config_string(value : String?) -> Bytes {
  @ffi.to_cstr(value.unwrap_or(""))
}

///|
fn runtime_config_languages(values : Array[String]) -> Bytes {
  @ffi.to_cstr(values.join(","))
}

///|
fn runtime_config_remote_debugging(value : RemoteDebugging) -> Int {
  match value {
    Disabled => 0
    Ephemeral => -1
    Fixed(port) => port
  }
}

///|
fn validate_runtime_config(config : RuntimeConfig) -> Unit raise NativeError {
  match config.remote_debugging {
    Fixed(port) if port < 1024 || port > 65535 =>
      raise invalid_argument(
        "runtime fixed remote debugging port must be between 1024 and 65535",
      )
    _ => ()
  }
  match config.cache_dir {
    Some(cache_dir) => {
      let path : @path.Path = cache_dir
      if !path.is_absolute() {
        raise invalid_argument("runtime cache_dir must be an absolute path")
      }
    }
    None => ()
  }
  if !config.use_bundled {
    if config.runtime_root is None {
      raise invalid_argument("runtime config requires runtime_root")
    }
    if config.helper_path is None {
      raise invalid_argument("runtime config requires helper_path")
    }
  }
}

///|
pub fn execute_process(
  config? : RuntimeConfig = RuntimeConfig::bundled(),
) -> ProcessResult raise NativeError {
  @native_ffi.ensure_cef_loader_linked()
  validate_runtime_config(config)
  let out_exit_code = Ref(0)
  let status = @native_ffi.execute_process(
    runtime_config_bool(config.use_bundled),
    runtime_config_string(config.runtime_root),
    runtime_config_string(config.helper_path),
    runtime_config_string(config.resources_dir),
    runtime_config_string(config.locales_dir),
    runtime_config_string(config.cache_dir),
    runtime_config_string(config.locale),
    runtime_config_languages(config.accept_languages),
    runtime_config_string(config.framework_dialog_ok_label),
    runtime_config_string(config.framework_dialog_cancel_label),
    runtime_config_remote_debugging(config.remote_debugging),
    runtime_config_bool(config.headless),
    runtime_config_bool(config.persist_session_cookies),
    out_exit_code,
  )
  if status < 0 {
    raise native_error(status)
  } else if status == proton_process_handled {
    ProcessResult::SubprocessHandled(out_exit_code.val)
  } else {
    ProcessResult::MainProcess
  }
}

///|
pub fn Runtime::Runtime(
  config? : RuntimeConfig = RuntimeConfig::bundled(),
) -> Runtime raise NativeError {
  @native_ffi.ensure_cef_loader_linked()
  validate_runtime_config(config)
  let out_runtime = Ref(@native_ffi.runtime_null())
  let status = @native_ffi.runtime_create(
    runtime_config_bool(config.use_bundled),
    runtime_config_string(config.runtime_root),
    runtime_config_string(config.helper_path),
    runtime_config_string(config.resources_dir),
    runtime_config_string(config.locales_dir),
    runtime_config_string(config.cache_dir),
    runtime_config_string(config.locale),
    runtime_config_languages(config.accept_languages),
    runtime_config_string(config.framework_dialog_ok_label),
    runtime_config_string(config.framework_dialog_cancel_label),
    runtime_config_remote_debugging(config.remote_debugging),
    runtime_config_bool(config.headless),
    runtime_config_bool(config.persist_session_cookies),
    out_runtime,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    Runtime::{ handle: out_runtime.val, lifecycle: RuntimeActive, }
  }
}

///|
pub fn Runtime::destroy(self : Runtime) -> Unit raise NativeError {
  match self.lifecycle {
    RuntimeDestroyed => return
    RuntimeActive | RuntimeDestroying => self.lifecycle = RuntimeDestroying
  }
  let status = @native_ffi.proton_runtime_destroy_ffi(self.handle)
  if status < 0 {
    raise native_error(status)
  } else {
    self.handle = @native_ffi.runtime_null()
    self.lifecycle = RuntimeDestroyed
  }
}

///|
fn Runtime::active_handle(
  self : Runtime,
) -> @native_ffi.RuntimeHandle raise NativeError {
  match self.lifecycle {
    RuntimeActive => self.handle
    RuntimeDestroying | RuntimeDestroyed =>
      raise Status(
        status=proton_err_invalid_state,
        message="runtime is destroying or destroyed",
      )
  }
}

///|
/// Encodes an optional wait timeout for the ABI. The sentinel lives here and
/// nowhere else: callers say `None` to wait indefinitely. A deadline that has
/// already passed is a zero wait rather than an error, because arriving late is
/// normal and is not a reason to refuse to poll.
fn encode_wait_timeout(timeout_ms : Int?) -> Int {
  match timeout_ms {
    None => runtime_wait_timeout_infinite
    Some(timeout_ms) => if timeout_ms < 0 { 0 } else { timeout_ms }
  }
}

///|
/// Takes over the calling thread's event loop. The loop belongs to the thread
/// rather than to a runtime: it starts before the first runtime exists and
/// outlives the last one, so a host can run async work while it is still
/// deciding what runtime to build.
///
/// Must be called on the process's main thread.
pub fn host_loop_begin() -> Unit raise NativeError {
  check_status(@native_ffi.proton_host_loop_begin_ffi())
}

///|
/// Runs one iteration of the host loop: block until work arrives or the
/// timeout expires, then advance the platform toolkit. Pass no `timeout_ms` to
/// wait indefinitely.
///
/// This is the only thing that drives the platform while the host loop owns the
/// thread, so a host must keep calling it. The returned mask says which kinds
/// of work became ready; it is empty when nothing happened.
pub fn host_loop_poll(timeout_ms? : Int) -> RuntimeWaitReady raise NativeError {
  let ready_mask = Ref(runtime_wait_none)
  let status = @native_ffi.proton_host_loop_poll_ffi(
    encode_wait_timeout(timeout_ms),
    ready_mask,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    RuntimeWaitReady::{ mask: ready_mask.val, }
  }
}

///|
/// Releases the host loop. Safe to call when no loop is running.
pub fn host_loop_end() -> Unit {
  @native_ffi.proton_host_loop_end_ffi()
}

///|
/// Wakes a blocked `host_loop_poll`, or makes the next one return immediately.
/// A lost wakeup deadlocks the host, so the two cases behave the same.
///
/// Takes no runtime and is safe from any thread, touching only atomics and the
/// platform run loop. That is what lets a thread outside the runtime call it:
/// handles validate thread ownership and such a thread owns none.
pub fn signal_wakeup() -> Unit {
  @native_ffi.proton_runtime_signal_wakeup_ffi()
}

///|
/// Returns the opaque native callback used by extension event producers.
pub fn event_wakeup_callback() -> @ffi.EventWakeup {
  @native_ffi.proton_runtime_event_wakeup_callback_ffi()
}

///|
fn menu_item_kind_code(kind : MenuItemKind) -> Int {
  match kind {
    Command => 0
    Separator => 1
    Role => 2
    Submenu => 3
  }
}

///|
fn menu_role_code(role : MenuRole?) -> Int {
  match role {
    None => 0
    Some(Application) => 1
    Some(File) => 2
    Some(Edit) => 3
    Some(View) => 4
    Some(Window) => 5
    Some(Help) => 6
  }
}

///|
fn menu_item_role_name(role : MenuItemRole?) -> String? {
  match role {
    None => None
    Some(Quit) => Some("quit")
    Some(Hide) => Some("hide")
    Some(HideOthers) => Some("hide_others")
    Some(ShowAll) => Some("show_all")
    Some(Close) => Some("close")
    Some(Minimize) => Some("minimize")
    Some(Zoom) => Some("zoom")
    Some(Undo) => Some("undo")
    Some(Redo) => Some("redo")
    Some(Cut) => Some("cut")
    Some(Copy) => Some("copy")
    Some(Paste) => Some("paste")
    Some(SelectAll) => Some("select_all")
  }
}

///|
fn build_menu_config(
  menu : MenuBar,
) -> @native_ffi.MenuConfigHandle raise NativeError {
  let out_menu = Ref(@native_ffi.menu_config_null())
  let create_status = @native_ffi.menu_config_create(out_menu)
  if create_status < 0 {
    raise native_error(create_status)
  }
  let handle = out_menu.val
  for definition in menu.menus {
    let menu_index = Ref(0)
    let menu_status = @native_ffi.menu_config_add_menu(
      handle,
      runtime_config_string(definition.label),
      menu_role_code(definition.role),
      menu_index,
    )
    if menu_status < 0 {
      @native_ffi.menu_config_destroy(handle)
      raise native_error(menu_status)
    }
    let items_status = append_menu_config_items(
      handle,
      definition.items.unwrap_or([]),
    )
    if items_status < 0 {
      @native_ffi.menu_config_destroy(handle)
      raise native_error(items_status)
    }
  }
  handle
}

///|
/// Recursively appends menu items to the current builder target, bracketing
/// nested submenus with begin/end submenu calls on the native config handle.
/// Returns the first negative status, or `0` on success.
fn append_menu_config_items(
  handle : @native_ffi.MenuConfigHandle,
  items : Array[MenuItem],
) -> Int {
  for item in items {
    match item.kind {
      Submenu => {
        let sub_menu = item.submenu.unwrap()
        let begin_status = @native_ffi.menu_config_begin_submenu(
          handle,
          runtime_config_string(sub_menu.label),
        )
        if begin_status < 0 {
          return begin_status
        }
        let child_status = append_menu_config_items(
          handle,
          sub_menu.items.unwrap_or([]),
        )
        if child_status < 0 {
          return child_status
        }
        let end_status = @native_ffi.menu_config_end_submenu(handle)
        if end_status < 0 {
          return end_status
        }
      }
      _ => {
        let add_status = @native_ffi.menu_config_add_item(
          handle,
          menu_item_kind_code(item.kind),
          runtime_config_string(item.id),
          runtime_config_string(item.label),
          runtime_config_string(item.key),
          runtime_config_string(menu_item_role_name(item.role)),
        )
        if add_status < 0 {
          return add_status
        }
      }
    }
  }
  0
}

///|
/// Replaces the application-level native menu bar for this runtime.
pub fn Runtime::set_menu(
  self : Runtime,
  menu : MenuBar,
) -> Unit raise NativeError {
  let config = build_menu_config(menu)
  let status = @native_ffi.runtime_set_menu(self.active_handle(), config)
  @native_ffi.menu_config_destroy(config)
  check_status(status)
}

///|
/// Pops up `menu` as a window-level context menu at view-relative
/// coordinates `(x, y)` (CSS pixels, top-left origin). Command items deliver
/// through the same runtime menu events as the application menu bar; role
/// items invoke their platform-native actions.
pub fn Window::popup_menu(
  self : Window,
  menu : MenuBar,
  x : Int,
  y : Int,
) -> Unit raise NativeError {
  let config = build_menu_config(menu)
  let status = @native_ffi.menu_popup(self.live_handle(), x, y, config)
  @native_ffi.menu_config_destroy(config)
  check_status(status)
}

///|
fn native_event_text(
  event : @native_ffi.EventHandle,
  field : Int,
) -> String? raise NativeError {
  read_native_text("runtime event JSON", (buffer, buffer_len, required) => {
    @native_ffi.event_text(event, field, buffer, buffer_len, required)
  })
}

///|
fn require_native_event_text(
  event : @native_ffi.EventHandle,
  field : Int,
  label : String,
) -> String raise NativeError {
  guard native_event_text(event, field) is Some(text) else {
    raise runtime_event_missing(label, "text")
  }
  text
}

///|
fn native_event_items(
  event : @native_ffi.EventHandle,
) -> Array[String] raise NativeError {
  let items : Array[String] = []
  let count = @native_ffi.event_item_count(event)
  for index = 0; index < count; index = index + 1 {
    let item = require_native_text("runtime event item", (
      buffer,
      buffer_len,
      required,
    ) => @native_ffi.event_item(event, index, buffer, buffer_len, required))
    items.push(item)
  }
  items
}

///|
fn window_state_from_fields(field : (Int) -> Int) -> WindowState {
  let theme = match field(20) {
    1 => "light"
    2 => "dark"
    _ => "system"
  }
  {
    x: field(0),
    y: field(1),
    width: field(2),
    height: field(3),
    monitor: {
      x: field(4),
      y: field(5),
      width: field(6),
      height: field(7),
      work_x: field(8),
      work_y: field(9),
      work_width: field(10),
      work_height: field(11),
      scale_factor_percent: field(12),
    },
    zoom_percent: field(13),
    visible: field(14) != 0,
    focused: field(15) != 0,
    minimized: field(16) != 0,
    maximized: field(17) != 0,
    fullscreen: field(18) != 0,
    always_on_top: field(19) != 0,
    theme,
  }
}

///|
fn native_window_state(event : @native_ffi.EventHandle) -> WindowState {
  window_state_from_fields(index => {
    @native_ffi.event_window_state_field(event, index)
  })
}

///|
fn decode_native_runtime_event(
  event : @native_ffi.EventHandle,
) -> RuntimeEvent raise NativeError {
  let window = @native_ffi.event_int64(event, 0)
  match @native_ffi.event_kind(event) {
    1 => WindowCreated(window)
    2 => WindowClosed(window)
    3 => WindowStateChanged(window, native_window_state(event))
    4 => WindowCloseRequested(window, @native_ffi.event_int64(event, 2))
    5 => BridgeLifecycleChanged(window, @native_ffi.event_int64(event, 3))
    6 => BridgeRequestCancelled(@native_ffi.event_int64(event, 2))
    7 => {
      let command_id = require_native_event_text(event, 0, "menu_command")
      MenuCommand(
        command_id,
        if window == proton_invalid_handle {
          None
        } else {
          Some(window)
        },
      )
    }
    8 => LaunchInput(OpenUrls(native_event_items(event)))
    9 => LaunchInput(OpenFiles(native_event_items(event)))
    10 => LaunchInput(Reopen)
    11 =>
      NotificationResult(
        if @native_ffi.event_int(event, 3) != 0 {
          Delivered
        } else {
          Failed(require_native_event_text(event, 0, "notification result"))
        },
      )
    12 =>
      BrowserRequest(
        window,
        Navigation(
          request_id=@native_ffi.event_int64(event, 2),
          url=require_native_event_text(event, 0, "browser navigation"),
          http_method=require_native_event_text(
            event, 1, "browser navigation method",
          ),
          user_gesture=@native_ffi.event_int(event, 3) != 0,
          redirect=@native_ffi.event_int(event, 4) != 0,
        ),
      )
    13 =>
      BrowserRequest(
        window,
        Popup(
          request_id=@native_ffi.event_int64(event, 2),
          url=require_native_event_text(event, 0, "browser popup"),
          disposition=@native_ffi.event_int(event, 0),
          user_gesture=@native_ffi.event_int(event, 3) != 0,
        ),
      )
    14 =>
      BrowserRequest(
        window,
        Download(
          request_id=@native_ffi.event_int64(event, 2),
          download_id=@native_ffi.event_int(event, 0),
          url=require_native_event_text(event, 0, "browser download"),
          suggested_name=require_native_event_text(
            event, 1, "browser download name",
          ),
        ),
      )
    15 =>
      BrowserRequest(
        window,
        Certificate(
          request_id=@native_ffi.event_int64(event, 2),
          url=require_native_event_text(event, 0, "browser certificate"),
          error_code=@native_ffi.event_int(event, 0),
        ),
      )
    16 =>
      BrowserRequest(
        window,
        Media(
          request_id=@native_ffi.event_int64(event, 2),
          origin=require_native_event_text(event, 0, "browser media"),
          permissions=@native_ffi.event_int(event, 0),
        ),
      )
    17 =>
      BrowserDownloadUpdated(window, {
        download_id: @native_ffi.event_int(event, 0),
        state: require_native_event_text(event, 0, "browser download update"),
        received_bytes: @native_ffi.event_int64(event, 4),
        total_bytes: @native_ffi.event_int64(event, 5),
        percent: @native_ffi.event_int(event, 1),
      })
    18 =>
      ViewEvent(
        window,
        @native_ffi.event_int64(event, 1),
        LoadingChanged(@native_ffi.event_int(event, 3) != 0),
      )
    19 =>
      ViewEvent(
        window,
        @native_ffi.event_int64(event, 1),
        Navigated(require_native_event_text(event, 0, "view navigation")),
      )
    20 =>
      ViewEvent(
        window,
        @native_ffi.event_int64(event, 1),
        TitleUpdated(require_native_event_text(event, 0, "view title")),
      )
    21 =>
      ViewEvent(
        window,
        @native_ffi.event_int64(event, 1),
        LoadFailed(
          require_native_event_text(event, 0, "view load URL"),
          @native_ffi.event_int(event, 0),
          require_native_event_text(event, 1, "view load error"),
        ),
      )
    22 =>
      BridgeRequestReceived(
        decode_bridge_request_json(
          require_native_event_text(event, 0, "bridge request"),
        ),
      )
    23 => {
      let status = @native_ffi.event_int(event, 0)
      DialogCompleted({
        dialog: @native_ffi.event_int64(event, 2),
        window: if window == proton_invalid_handle {
          None
        } else {
          Some(window)
        },
        result: if status == 0 {
          Ok(require_native_event_text(event, 0, "dialog result"))
        } else {
          Err(
            Status(
              status~,
              message=require_native_event_text(event, 1, "dialog error"),
            ),
          )
        },
      })
    }
    24 => {
      let status = @native_ffi.event_int(event, 0)
      CookieGetCompleted({
        request_id: @native_ffi.event_int64(event, 2),
        window,
        result: if status == 0 {
          Ok(require_native_event_text(event, 0, "cookie result"))
        } else {
          Err(
            Status(
              status~,
              message=require_native_event_text(event, 1, "cookie error"),
            ),
          )
        },
      })
    }
    25 =>
      ResourceRequested({
        request_id: @native_ffi.event_int64(event, 2),
        window,
        view: {
          let view = @native_ffi.event_int64(event, 1)
          if view == proton_invalid_handle {
            None
          } else {
            Some(view)
          }
        },
        url: require_native_event_text(event, 0, "resource request"),
      })
    26 => ResourceRequestCancelled(@native_ffi.event_int64(event, 2))
    27 =>
      NotificationClicked(
        if @native_ffi.event_int(event, 3) == 0 {
          None
        } else {
          Some(require_native_event_text(event, 0, "notification click"))
        },
      )
    28 => QuitRequested
    29 => ViewEvent(window, @native_ffi.event_int64(event, 1), Closed)
    kind =>
      raise InvalidPayload(
        context="runtime event",
        message="unsupported native event kind " + kind.to_string(),
      )
  }
}

///|
pub fn Runtime::poll_event(self : Runtime) -> RuntimeEvent? raise NativeError {
  let out_event = Ref(@native_ffi.event_null())
  let status = @native_ffi.runtime_poll_event(self.active_handle(), out_event)
  if status == proton_event_none {
    return None
  }
  if status < 0 {
    raise native_error(status)
  }
  defer @native_ffi.event_destroy(out_event.val)
  Some(decode_native_runtime_event(out_event.val))
}

///|
pub fn Runtime::respond_bridge_request(
  self : Runtime,
  response : BridgeResponse,
) -> Unit raise NativeError {
  let (request_id, ok, body_json) = match response {
    Ok(request_id~, payload~) => (request_id, 1, payload.stringify())
    Err(request_id~, code~, message~) => {
      let error : Json = { "code": code, "message": message }
      (request_id, 0, error.stringify())
    }
  }
  check_status(
    @native_ffi.proton_runtime_respond_bridge_request_ffi(
      self.active_handle(),
      request_id,
      ok,
      @ffi.to_cstr(body_json),
    ),
  )
}

///|
pub fn Runtime::complete_resource_request(
  self : Runtime,
  request_id : Int64,
  status : Int,
  mime_type : String,
  data : Bytes,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.runtime_complete_resource_request(
      self.active_handle(),
      request_id,
      status,
      @ffi.to_cstr(mime_type),
      data,
      data.length(),
    ),
  )
}

///|
fn bridge_config_check(
  config : @native_ffi.BridgeConfigHandle,
  status : Int,
) -> Unit raise NativeError {
  if status < 0 {
    @native_ffi.bridge_config_destroy(config)
    raise native_error(status)
  }
}

///|
fn build_bridge_config(
  config : BridgeConfig?,
) -> @native_ffi.BridgeConfigHandle raise NativeError {
  guard config is Some(config) else { return @native_ffi.bridge_config_null() }
  let out_config = Ref(@native_ffi.bridge_config_null())
  let create_status = @native_ffi.bridge_config_create(
    config.max_payload_bytes,
    out_config,
  )
  if create_status < 0 {
    raise native_error(create_status)
  }
  let handle = out_config.val
  for grant in config.grants {
    let grant_index = Ref(0)
    bridge_config_check(
      handle,
      @native_ffi.bridge_config_add_grant(
        handle,
        @ffi.to_cstr(grant.source_origin),
        grant_index,
      ),
    )
    for op in grant.ops {
      bridge_config_check(
        handle,
        @native_ffi.bridge_config_add_op(
          handle,
          grant_index.val,
          @ffi.to_cstr(op),
        ),
      )
    }
    for extension in grant.extensions {
      let extension_index = Ref(0)
      bridge_config_check(
        handle,
        @native_ffi.bridge_config_add_extension(
          handle,
          grant_index.val,
          @ffi.to_cstr(extension.js_namespace),
          extension_index,
        ),
      )
      for api in extension.apis {
        bridge_config_check(
          handle,
          @native_ffi.bridge_config_add_extension_api(
            handle,
            grant_index.val,
            extension_index.val,
            @ffi.to_cstr(api),
          ),
        )
      }
    }
    for unit in grant.initialization_units {
      bridge_config_check(
        handle,
        @native_ffi.bridge_config_add_initialization_unit(
          handle,
          grant_index.val,
          @ffi.to_cstr(unit.owner),
          @ffi.to_cstr(unit.name),
          @ffi.to_cstr(unit.source),
        ),
      )
    }
  }
  handle
}

///|
pub fn Window::Window(
  runtime : Runtime,
  config? : WindowConfig = WindowConfig(),
) -> Window raise NativeError {
  validate_window_config(config)
  let out_window = Ref(@native_ffi.window_null())
  let bridge_config = build_bridge_config(config.bridge)
  let status = @native_ffi.window_create(
    runtime.active_handle(),
    @ffi.to_cstr(config.title),
    config.width,
    config.height,
    @ffi.to_cstr(config.initial_url),
    window_size_hint_code(config.size_hint),
    runtime_config_bool(config.titlebar_style is TitlebarStyle::Overlay),
    browser_policy_code(config.browser.navigation),
    runtime_config_string(config.framework_titlebar_minimize_label),
    runtime_config_string(config.framework_titlebar_maximize_label),
    runtime_config_string(config.framework_titlebar_restore_label),
    runtime_config_string(config.framework_titlebar_close_label),
    browser_policy_code(config.browser.popup),
    browser_policy_code(config.browser.download),
    browser_policy_code(config.browser.certificate),
    browser_policy_code(config.browser.media),
    runtime_config_bool(config.browser.devtools),
    bridge_config,
    out_window,
  )
  @native_ffi.bridge_config_destroy(bridge_config)
  if status < 0 {
    raise native_error(status)
  } else {
    Window::{
      handle: out_window.val,
      id: @native_ffi.window_logical_id(out_window.val),
      lifecycle: WindowLive,
    }
  }
}

///|
pub fn Window::destroy(self : Window) -> Unit raise NativeError {
  match self.lifecycle {
    WindowDestroyed => return
    WindowLive | WindowCloseRequested | WindowDestroying =>
      self.lifecycle = WindowDestroying
  }
  let status = @native_ffi.proton_window_destroy_ffi(self.handle)
  if status < 0 {
    raise native_error(status)
  } else {
    self.handle = @native_ffi.window_null()
    self.lifecycle = WindowDestroyed
  }
}

///|
fn Window::live_handle(
  self : Window,
) -> @native_ffi.WindowHandle raise NativeError {
  match self.lifecycle {
    WindowLive => self.handle
    WindowCloseRequested | WindowDestroying | WindowDestroyed =>
      raise Status(
        status=proton_err_invalid_state,
        message="window is closing or destroyed",
      )
  }
}

///|
pub fn Window::show(self : Window) -> Unit raise NativeError {
  check_status(@native_ffi.proton_window_show_ffi(self.live_handle()))
}

///|
pub fn Window::show_inactive(self : Window) -> Unit raise NativeError {
  check_status(@native_ffi.proton_window_show_inactive_ffi(self.live_handle()))
}

///|
/// Borrows this owning window handle for APIs that must not destroy it.
pub fn Window::as_ref(self : Window) -> WindowRef {
  WindowRef::unsafe_from_handle(
    match self.lifecycle {
      WindowLive => self.handle
      WindowCloseRequested | WindowDestroying | WindowDestroyed =>
        @native_ffi.window_null()
    },
  )
}

///|
/// Returns the stable native handle used to correlate runtime events.
pub fn Window::id(self : Window) -> Int64 {
  match self.lifecycle {
    WindowLive | WindowCloseRequested => self.id
    WindowDestroying | WindowDestroyed => proton_invalid_handle
  }
}

///|
pub fn Window::hide(self : Window) -> Unit raise NativeError {
  check_status(@native_ffi.proton_window_hide_ffi(self.live_handle()))
}

///|
pub fn Window::close(self : Window) -> Unit raise NativeError {
  match self.lifecycle {
    WindowCloseRequested | WindowDestroying | WindowDestroyed => return
    WindowLive => ()
  }
  let status = @native_ffi.proton_window_close_ffi(self.handle)
  if status < 0 {
    raise native_error(status)
  } else {
    self.lifecycle = WindowCloseRequested
  }
}

///|
pub fn Window::focus(self : Window) -> Unit raise NativeError {
  check_status(@native_ffi.proton_window_focus_ffi(self.live_handle()))
}

///|
pub fn Window::set_title(
  self : Window,
  title : String,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_title_ffi(
      self.live_handle(),
      @ffi.to_cstr(title),
    ),
  )
}

///|
/// Sets the native window icon from an image file path.
pub fn Window::set_icon(self : Window, path : String) -> Unit raise NativeError {
  if path.length() == 0 {
    raise invalid_argument("icon path must not be empty")
  }
  check_status(
    @native_ffi.proton_window_set_icon_ffi(
      self.live_handle(),
      @ffi.to_cstr(path),
    ),
  )
}

///|
/// Establishes or clears this window's native parent relationship.
pub fn Window::set_parent(
  self : Window,
  parent : WindowRef?,
  modal : Bool,
) -> Unit raise NativeError {
  let parent_handle = match parent {
    Some(parent) => parent.handle
    None => @native_ffi.window_null()
  }
  check_status(
    @native_ffi.proton_window_set_parent_ffi(
      self.live_handle(),
      parent_handle,
      if modal {
        1
      } else {
        0
      },
    ),
  )
}

///|
pub fn Window::set_size(
  self : Window,
  width : Int,
  height : Int,
) -> Unit raise NativeError {
  if width <= 0 || height <= 0 {
    raise invalid_argument("width and height must be positive")
  }
  check_status(
    @native_ffi.proton_window_set_size_ffi(self.live_handle(), width, height),
  )
}

///|
/// Sets the live renderer content area in logical pixels.
pub fn Window::set_content_size(
  self : Window,
  width : Int,
  height : Int,
) -> Unit raise NativeError {
  if width <= 0 || height <= 0 {
    raise invalid_argument("width and height must be positive")
  }
  check_status(
    @native_ffi.proton_window_set_content_size_ffi(
      self.live_handle(),
      width,
      height,
    ),
  )
}

///|
/// Returns the live renderer content area in logical pixels.
pub fn Window::content_size(self : Window) -> (Int, Int) raise NativeError {
  let width : Ref[Int] = { val: 0, }
  let height : Ref[Int] = { val: 0, }
  check_status(
    @native_ffi.proton_window_get_content_size_ffi(
      self.live_handle(),
      width,
      height,
    ),
  )
  (width.val, height.val)
}

///|
pub fn Window::minimize(self : Window) -> Unit raise NativeError {
  check_status(@native_ffi.proton_window_minimize_ffi(self.live_handle()))
}

///|
pub fn Window::maximize(self : Window) -> Unit raise NativeError {
  check_status(@native_ffi.proton_window_maximize_ffi(self.live_handle()))
}

///|
pub fn Window::restore(self : Window) -> Unit raise NativeError {
  check_status(@native_ffi.proton_window_restore_ffi(self.live_handle()))
}

///|
pub fn Window::set_fullscreen(
  self : Window,
  fullscreen : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_fullscreen_ffi(
      self.live_handle(),
      if fullscreen {
        1
      } else {
        0
      },
    ),
  )
}

///|
pub fn Window::set_kiosk(self : Window, kiosk : Bool) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_kiosk_ffi(
      self.live_handle(),
      if kiosk {
        1
      } else {
        0
      },
    ),
  )
}

///|
pub fn Window::set_position(
  self : Window,
  x : Int,
  y : Int,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_position_ffi(self.live_handle(), x, y),
  )
}

///|
pub fn Window::set_always_on_top(
  self : Window,
  always_on_top : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_always_on_top_ffi(
      self.live_handle(),
      if always_on_top {
        1
      } else {
        0
      },
    ),
  )
}

///|
/// Sets whether the live native window can be manually resized.
pub fn Window::set_resizable(
  self : Window,
  resizable : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_resizable_ffi(
      self.live_handle(),
      if resizable {
        1
      } else {
        0
      },
    ),
  )
}

///|
/// Sets the minimum live native window size. `(0, 0)` clears the constraint.
pub fn Window::set_minimum_size(
  self : Window,
  width : Int,
  height : Int,
) -> Unit raise NativeError {
  validate_size_constraint(width, height, "minimum")
  check_status(
    @native_ffi.proton_window_set_minimum_size_ffi(
      self.live_handle(),
      width,
      height,
    ),
  )
}

///|
/// Sets the maximum live native window size. `(0, 0)` clears the constraint.
pub fn Window::set_maximum_size(
  self : Window,
  width : Int,
  height : Int,
) -> Unit raise NativeError {
  validate_size_constraint(width, height, "maximum")
  check_status(
    @native_ffi.proton_window_set_maximum_size_ffi(
      self.live_handle(),
      width,
      height,
    ),
  )
}

///|
/// Sets the live native window aspect ratio. Pass `0.0` to clear the ratio.
pub fn Window::set_aspect_ratio(
  self : Window,
  aspect_ratio : Double,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_aspect_ratio_ffi(
      self.live_handle(),
      aspect_ratio,
    ),
  )
}

///|
/// Sets whether the user can move the live native window.
pub fn Window::set_movable(
  self : Window,
  movable : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_movable_ffi(
      self.live_handle(),
      if movable {
        1
      } else {
        0
      },
    ),
  )
}

///|
/// Sets the opacity of the live native window, clamped to `0.0..1.0`.
pub fn Window::set_opacity(
  self : Window,
  opacity : Double,
) -> Unit raise NativeError {
  if opacity.is_nan() {
    raise invalid_argument("opacity must not be NaN")
  }
  let bounded_opacity = if opacity < 0.0 {
    0.0
  } else if opacity > 1.0 {
    1.0
  } else {
    opacity
  }
  check_status(
    @native_ffi.proton_window_set_opacity_ffi(
      self.live_handle(),
      bounded_opacity,
    ),
  )
}

///|
/// Sets whether the live native window is omitted from the taskbar or dock.
pub fn Window::set_skip_taskbar(
  self : Window,
  skip : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_skip_taskbar_ffi(
      self.live_handle(),
      if skip {
        1
      } else {
        0
      },
    ),
  )
}

///|
/// Sets whether other applications should be prevented from capturing the
/// live native window.
pub fn Window::set_content_protection(
  self : Window,
  enabled : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_content_protection_ffi(
      self.live_handle(),
      if enabled {
        1
      } else {
        0
      },
    ),
  )
}

///|
/// Sets whether the user can manually minimize the live native window.
pub fn Window::set_minimizable(
  self : Window,
  minimizable : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_minimizable_ffi(
      self.live_handle(),
      if minimizable {
        1
      } else {
        0
      },
    ),
  )
}

///|
/// Sets whether the user can manually maximize the live native window.
pub fn Window::set_maximizable(
  self : Window,
  maximizable : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_maximizable_ffi(
      self.live_handle(),
      if maximizable {
        1
      } else {
        0
      },
    ),
  )
}

///|
/// Sets whether the user can manually close the live native window.
pub fn Window::set_closable(
  self : Window,
  closable : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_closable_ffi(
      self.live_handle(),
      if closable {
        1
      } else {
        0
      },
    ),
  )
}

///|
/// Sets visibility of the standard native window buttons.
pub fn Window::set_button_visibility(
  self : Window,
  visible : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_button_visibility_ffi(
      self.live_handle(),
      if visible {
        1
      } else {
        0
      },
    ),
  )
}

///|
/// Sets whether the live native window can receive focus.
pub fn Window::set_focusable(
  self : Window,
  focusable : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_focusable_ffi(
      self.live_handle(),
      if focusable {
        1
      } else {
        0
      },
    ),
  )
}

///|
pub fn Window::set_fullscreenable(
  self : Window,
  fullscreenable : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_fullscreenable_ffi(
      self.live_handle(),
      if fullscreenable {
        1
      } else {
        0
      },
    ),
  )
}

///|
pub fn Window::set_has_shadow(
  self : Window,
  has_shadow : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_has_shadow_ffi(
      self.live_handle(),
      if has_shadow {
        1
      } else {
        0
      },
    ),
  )
}

///|
pub fn Window::set_ignore_mouse_events(
  self : Window,
  ignore : Bool,
  forward : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_ignore_mouse_events_ffi(
      self.live_handle(),
      if ignore {
        1
      } else {
        0
      },
      if forward {
        1
      } else {
        0
      },
    ),
  )
}

///|
pub fn Window::set_background_color(
  self : Window,
  color : String,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_background_color_ffi(
      self.live_handle(),
      @utf8.encode(color),
    ),
  )
}

///|
pub fn Window::set_visible_on_all_workspaces(
  self : Window,
  visible : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_visible_on_all_workspaces_ffi(
      self.live_handle(),
      if visible {
        1
      } else {
        0
      },
    ),
  )
}

///|
pub fn Window::set_enabled(
  self : Window,
  enabled : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_enabled_ffi(
      self.live_handle(),
      if enabled {
        1
      } else {
        0
      },
    ),
  )
}

///|
pub fn Window::set_zoom_percent(
  self : Window,
  zoom_percent : Int,
) -> Unit raise NativeError {
  if zoom_percent < 25 || zoom_percent > 500 {
    raise invalid_argument("zoom_percent must be between 25 and 500")
  }
  check_status(
    @native_ffi.proton_window_set_zoom_percent_ffi(
      self.live_handle(),
      zoom_percent,
    ),
  )
}

///|
/// Sets the platform progress indicator for this window.
///
/// A negative value clears the indicator, values from `0.0` through `1.0`
/// display determinate progress, and a value above `1.0` displays an
/// indeterminate indicator.
pub fn Window::set_progress_bar(
  self : Window,
  progress : Double,
) -> Unit raise NativeError {
  if progress.is_nan() {
    raise invalid_argument("progress must not be NaN")
  }
  check_status(
    @native_ffi.proton_window_set_progress_bar_ffi(self.live_handle(), progress),
  )
}

///|
/// Starts or stops the platform window-attention indicator.
pub fn Window::flash_frame(
  self : Window,
  flash : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_flash_frame_ffi(
      self.live_handle(),
      if flash {
        1
      } else {
        0
      },
    ),
  )
}

///|
pub fn Window::state(self : Window) -> WindowState raise NativeError {
  let fields = FixedArray::make(proton_window_state_field_count, 0)
  check_status(
    @native_ffi.proton_window_get_state_ffi(
      self.live_handle(),
      fields,
      fields.length(),
    ),
  )
  window_state_from_fields(index => fields[index])
}

///|
/// Returns whether the main browser has backward and forward history.
pub fn Window::navigation_state(
  self : Window,
) -> (Bool, Bool) raise NativeError {
  let can_go_back : Ref[Int] = { val: 0, }
  let can_go_forward : Ref[Int] = { val: 0, }
  check_status(
    @native_ffi.proton_window_get_navigation_state_ffi(
      self.live_handle(),
      can_go_back,
      can_go_forward,
    ),
  )
  (can_go_back.val != 0, can_go_forward.val != 0)
}

///|
pub fn Window::set_close_interception(
  self : Window,
  enabled : Bool,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_set_close_interception_ffi(
      self.live_handle(),
      if enabled {
        1
      } else {
        0
      },
    ),
  )
}

///|
pub fn Window::respond_close_request(
  self : Window,
  request_id : Int64,
  allow : Bool,
) -> Unit raise NativeError {
  match self.lifecycle {
    WindowLive | WindowCloseRequested => ()
    WindowDestroying | WindowDestroyed =>
      raise Status(
        status=proton_err_invalid_state,
        message="window is closing or destroyed",
      )
  }
  let status = @native_ffi.proton_window_respond_close_request_ffi(
    self.handle,
    request_id,
    if allow {
      1
    } else {
      0
    },
  )
  check_status(status)
  self.lifecycle = if allow { WindowCloseRequested } else { WindowLive }
}

///|
pub fn Window::load_url(self : Window, url : String) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_load_url_ffi(
      self.live_handle(),
      @ffi.to_cstr(url),
    ),
  )
}

///|
pub fn Window::eval(self : Window, script : String) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_eval_ffi(self.live_handle(), @ffi.to_cstr(script)),
  )
}

///|
pub fn Window::browser_command(
  self : Window,
  command : String,
  download_id? : Int,
) -> Unit raise NativeError {
  let fields : Map[String, Json] = { "command": command }
  match download_id {
    Some(download_id) =>
      fields["download_id"] = Json::number(
        download_id.to_double(),
        repr=download_id.to_string(),
      )
    None => ()
  }
  check_status(
    @native_ffi.proton_window_browser_command_json_ffi(
      self.live_handle(),
      @ffi.to_cstr(Json::object(fields).stringify()),
    ),
  )
}

///|
pub fn Window::respond_browser_request(
  self : Window,
  request_id : Int64,
  action : String,
  path? : String,
) -> Unit raise NativeError {
  let fields : Map[String, Json] = {
    "request_id": request_id.to_string(),
    "action": action,
  }
  match path {
    Some(path) => fields["path"] = Json(path)
    None => ()
  }
  check_status(
    @native_ffi.proton_window_respond_browser_request_json_ffi(
      self.live_handle(),
      @ffi.to_cstr(Json::object(fields).stringify()),
    ),
  )
}

///|
pub fn Window::emit_bridge_event_json(
  self : Window,
  event_json : String,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_window_emit_bridge_event_json_ffi(
      self.live_handle(),
      @ffi.to_cstr(event_json),
    ),
  )
}

///|
fn window_bridge_json(
  window : Window,
  context : String,
  query : (@native_ffi.WindowHandle, FixedArray[Byte], Int, Ref[Int]) -> Int,
) -> String? raise NativeError {
  let handle = window.live_handle()
  read_native_text(context, (buffer, buffer_len, required) => {
    query(handle, buffer, buffer_len, required)
  })
}

///|
fn decode_bridge_lifecycle_state(
  text : String,
) -> BridgeLifecycleState raise NativeError {
  let json = decode_native_json(text, "bridge lifecycle state")
  let state : BridgeLifecycleState = @json.from_json(json) catch {
    error =>
      raise InvalidPayload(
        context="bridge lifecycle state",
        message=error.to_string(),
      )
  }
  expect_abi_version(state.abi_version, "bridge lifecycle state")
  state
}

///|
pub fn Window::bridge_lifecycle_state(
  self : Window,
) -> BridgeLifecycleState raise NativeError {
  let text = match
    window_bridge_json(
      self, "bridge lifecycle state", @native_ffi.proton_window_bridge_state_json_ffi,
    ) {
    Some(text) => text
    None =>
      raise InvalidPayload(
        context="bridge lifecycle state",
        message="missing payload",
      )
  }
  decode_bridge_lifecycle_state(text)
}

///|
fn decode_bridge_diagnostic(
  text : String,
) -> BridgeDiagnostic raise NativeError {
  let json = decode_native_json(text, "bridge diagnostic")
  let diagnostic : BridgeDiagnostic = @json.from_json(json) catch {
    error =>
      raise InvalidPayload(
        context="bridge diagnostic",
        message=error.to_string(),
      )
  }
  expect_abi_version(diagnostic.abi_version, "bridge diagnostic")
  diagnostic
}

///|
pub fn Window::take_bridge_failure(
  self : Window,
) -> BridgeDiagnostic? raise NativeError {
  match
    window_bridge_json(
      self, "bridge diagnostic", @native_ffi.proton_window_take_bridge_failure_json_ffi,
    ) {
    None => None
    Some(text) => Some(decode_bridge_diagnostic(text))
  }
}

///|
/// Begins retrieving cookies for the window's session. Completion is delivered
/// as a `cookie_get_completed` runtime event carrying the returned request id.
pub fn Window::cookie_begin_get(
  self : Window,
  url : String?,
  include_http_only : Bool,
) -> Int64 raise NativeError {
  let url_bytes = match url {
    Some(u) => @ffi.to_cstr(u)
    None => @ffi.to_cstr("")
  }
  let request_id = Ref(proton_invalid_handle)
  check_status(
    @native_ffi.proton_window_cookie_begin_get_json_ffi(
      self.live_handle(),
      url_bytes,
      if include_http_only {
        1
      } else {
        0
      },
      request_id,
    ),
  )
  request_id.val
}

///|
/// Sets a cookie for the window's session. Fire-and-forget.
pub fn Window::cookie_set(
  self : Window,
  url : String,
  name : String,
  value : String,
  domain? : String,
  path? : String,
  secure? : Bool = false,
  http_only? : Bool = false,
  same_site? : CookieSameSite = Unspecified,
) -> Unit raise NativeError {
  if url.is_empty() {
    raise invalid_argument("cookie url must not be empty")
  }
  if name.is_empty() {
    raise invalid_argument("cookie name must not be empty")
  }
  check_status(
    @native_ffi.proton_window_cookie_set_ffi(
      self.live_handle(),
      @ffi.to_cstr(url),
      @ffi.to_cstr(name),
      @ffi.to_cstr(value),
      @ffi.to_cstr(domain.unwrap_or("")),
      @ffi.to_cstr(path.unwrap_or("")),
      if secure {
        1
      } else {
        0
      },
      if http_only {
        1
      } else {
        0
      },
      same_site.native_value(),
    ),
  )
}

///|
/// Deletes cookies. If `url` is `None`, all cookies are deleted. If `name`
/// is `Some`, only cookies with that name matching the URL are deleted.
/// Fire-and-forget.
pub fn Window::cookie_delete(
  self : Window,
  url : String?,
  name : String?,
) -> Unit raise NativeError {
  let url_bytes = match url {
    Some(u) => @ffi.to_cstr(u)
    None => @ffi.to_cstr("")
  }
  let name_bytes = match name {
    Some(n) => @ffi.to_cstr(n)
    None => @ffi.to_cstr("")
  }
  check_status(
    @native_ffi.proton_window_cookie_delete_ffi(
      self.live_handle(),
      url_bytes,
      name_bytes,
    ),
  )
}

///|
/// Flushes the cookie store to disk. Fire-and-forget.
pub fn Window::cookie_flush(self : Window) -> Unit raise NativeError {
  check_status(@native_ffi.proton_window_cookie_flush_ffi(self.live_handle()))
}

///|
/// Clears the HTTP cache for the window's request context. Fire-and-forget.
pub fn Window::clear_cache(self : Window) -> Unit raise NativeError {
  check_status(@native_ffi.proton_window_clear_cache_ffi(self.live_handle()))
}

///|
/// Creates an empty native image. Use `add_png`, `add_jpeg`, or `add_bitmap`
/// to add a representation at a given scale factor, then query with `is_empty`
/// or `size`, and export with `to_png`, `to_jpeg`, or `to_bitmap`.
///
/// Raises `UnsupportedNativeFeature` when the native engine is not available.
pub fn NativeImage::create_empty() -> NativeImage raise NativeError {
  let out_image = Ref(@native_ffi.image_null())
  check_status(@native_ffi.proton_image_create_empty_ffi(out_image))
  NativeImage::{ handle: out_image.val, lifecycle: ImageLive, }
}

///|
fn NativeImage::live_handle(
  self : NativeImage,
) -> @native_ffi.ImageHandle raise NativeError {
  match self.lifecycle {
    ImageLive => self.handle
    ImageDestroyed =>
      raise Status(
        status=proton_err_invalid_state,
        message="image is destroyed",
      )
  }
}

///|
/// Releases the native image handle. Safe to call multiple times; subsequent
/// calls are no-ops.
pub fn NativeImage::destroy(self : NativeImage) -> Unit raise NativeError {
  match self.lifecycle {
    ImageDestroyed => return
    ImageLive => self.lifecycle = ImageDestroyed
  }
  let status = @native_ffi.proton_image_destroy_ffi(self.handle)
  self.handle = @native_ffi.image_null()
  check_status(status)
}

///|
/// Adds a PNG representation at `scale_factor` (1.0 = 100%). PNG transparency
/// is preserved.
pub fn NativeImage::add_png(
  self : NativeImage,
  data : Bytes,
  scale_factor? : Double = 1.0,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_image_add_png_ffi(
      self.live_handle(),
      data,
      data.length(),
      scale_factor,
    ),
  )
}

///|
/// Adds a JPEG representation at `scale_factor` (1.0 = 100%). JPEG does not
/// support transparency; the alpha channel is discarded.
pub fn NativeImage::add_jpeg(
  self : NativeImage,
  data : Bytes,
  scale_factor? : Double = 1.0,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_image_add_jpeg_ffi(
      self.live_handle(),
      data,
      data.length(),
      scale_factor,
    ),
  )
}

///|
/// Adds a raw RGBA bitmap representation at `scale_factor` (1.0 = 100%).
/// `data` must be at least `width * height * 4` bytes in 32-bit RGBA format.
pub fn NativeImage::add_bitmap(
  self : NativeImage,
  data : Bytes,
  width : Int,
  height : Int,
  scale_factor? : Double = 1.0,
) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_image_add_bitmap_ffi(
      self.live_handle(),
      data,
      data.length(),
      width,
      height,
      scale_factor,
    ),
  )
}

///|
/// Returns `true` if the image has no representations.
pub fn NativeImage::is_empty(self : NativeImage) -> Bool raise NativeError {
  let status = @native_ffi.proton_image_is_empty_ffi(self.live_handle())
  if status < 0 {
    raise native_error(status)
  }
  status == 1
}

///|
/// Returns the image size in density-independent pixels as `(width, height)`.
pub fn NativeImage::size(self : NativeImage) -> (Int, Int) raise NativeError {
  let width = Ref(0)
  let height = Ref(0)
  check_status(
    @native_ffi.proton_image_get_size_ffi(self.live_handle(), width, height),
  )
  (width.val, height.val)
}

///|
/// Exports the representation closest to `scale_factor` as PNG bytes.
/// When `with_transparency` is `true`, alpha transparency is preserved.
/// Returns `(png_bytes, pixel_width, pixel_height)`.
pub fn NativeImage::to_png(
  self : NativeImage,
  scale_factor? : Double = 1.0,
  with_transparency? : Bool = true,
) -> (Bytes, Int, Int) raise NativeError {
  let handle = self.live_handle()
  let out_width = Ref(0)
  let out_height = Ref(0)
  let data = read_native_bytes("image to_png", (buffer, buffer_len, req) => {
    @native_ffi.proton_image_to_png_ffi(
      handle,
      scale_factor,
      if with_transparency {
        1
      } else {
        0
      },
      buffer,
      buffer_len,
      req,
      out_width,
      out_height,
    )
  })
  (data, out_width.val, out_height.val)
}

///|
/// Exports the representation closest to `scale_factor` as JPEG bytes.
/// `quality` is 0-100 (0=lowest, 100=highest). Returns
/// `(jpeg_bytes, pixel_width, pixel_height)`.
pub fn NativeImage::to_jpeg(
  self : NativeImage,
  scale_factor? : Double = 1.0,
  quality? : Int = 80,
) -> (Bytes, Int, Int) raise NativeError {
  let handle = self.live_handle()
  let out_width = Ref(0)
  let out_height = Ref(0)
  let data = read_native_bytes("image to_jpeg", (buffer, buffer_len, req) => {
    @native_ffi.proton_image_to_jpeg_ffi(
      handle, scale_factor, quality, buffer, buffer_len, req, out_width, out_height,
    )
  })
  (data, out_width.val, out_height.val)
}

///|
/// Exports the representation closest to `scale_factor` as raw RGBA bitmap
/// bytes (32-bit RGBA). Returns `(bitmap_bytes, pixel_width, pixel_height)`.
pub fn NativeImage::to_bitmap(
  self : NativeImage,
  scale_factor? : Double = 1.0,
) -> (Bytes, Int, Int) raise NativeError {
  let handle = self.live_handle()
  let out_width = Ref(0)
  let out_height = Ref(0)
  let data = read_native_bytes("image to_bitmap", (buffer, buffer_len, req) => {
    @native_ffi.proton_image_to_bitmap_ffi(
      handle, scale_factor, buffer, buffer_len, req, out_width, out_height,
    )
  })
  (data, out_width.val, out_height.val)
}

///|
fn optional_dialog_text_buffer(value : String?) -> Bytes {
  match value {
    Some(value) => @ffi.to_cstr(value)
    None => @ffi.to_cstr("")
  }
}

///|
fn dialog_text_payload_len(buffer : Bytes) -> Int {
  let len = buffer.length()
  if len >= 1 {
    len - 1
  } else {
    len
  }
}

///|
pub fn WindowRef::begin_message_dialog(
  self : WindowRef,
  title : String?,
  message : String,
  level : DialogLevel,
) -> Int64 raise NativeError {
  let title_buffer = optional_dialog_text_buffer(title)
  let message_buffer = @ffi.to_cstr(message)
  let dialog = Ref(proton_invalid_handle)
  let status = @native_ffi.proton_window_begin_message_dialog_ffi(
    self.handle,
    title_buffer,
    dialog_text_payload_len(title_buffer),
    message_buffer,
    dialog_text_payload_len(message_buffer),
    level.native_value(),
    dialog,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    dialog.val
  }
}

///|
pub fn Runtime::begin_message_dialog(
  self : Runtime,
  title : String?,
  message : String,
  level : DialogLevel,
) -> Int64 raise NativeError {
  let title_buffer = optional_dialog_text_buffer(title)
  let message_buffer = @ffi.to_cstr(message)
  let dialog = Ref(proton_invalid_handle)
  let status = @native_ffi.proton_runtime_begin_message_dialog_ffi(
    self.active_handle(),
    title_buffer,
    dialog_text_payload_len(title_buffer),
    message_buffer,
    dialog_text_payload_len(message_buffer),
    level.native_value(),
    dialog,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    dialog.val
  }
}

///|
pub fn WindowRef::begin_confirm_dialog(
  self : WindowRef,
  title : String?,
  message : String,
  level : DialogLevel,
) -> Int64 raise NativeError {
  let title_buffer = optional_dialog_text_buffer(title)
  let message_buffer = @ffi.to_cstr(message)
  let dialog = Ref(proton_invalid_handle)
  let status = @native_ffi.proton_window_begin_confirm_dialog_ffi(
    self.handle,
    title_buffer,
    dialog_text_payload_len(title_buffer),
    message_buffer,
    dialog_text_payload_len(message_buffer),
    level.native_value(),
    dialog,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    dialog.val
  }
}

///|
fn WindowRef::begin_file_dialog(
  window : WindowRef,
  title : String?,
  path : String?,
  callback : (@native_ffi.WindowHandle, Bytes, Int, Bytes, Int, Ref[Int64]) -> Int,
) -> Int64 raise NativeError {
  let title_buffer = optional_dialog_text_buffer(title)
  let path_buffer = optional_dialog_text_buffer(path)
  let dialog = Ref(proton_invalid_handle)
  let status = callback(
    window.handle,
    title_buffer,
    dialog_text_payload_len(title_buffer),
    path_buffer,
    dialog_text_payload_len(path_buffer),
    dialog,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    dialog.val
  }
}

///|
pub fn WindowRef::begin_open_file_dialog(
  self : WindowRef,
  title : String?,
  path : String?,
) -> Int64 raise NativeError {
  self.begin_file_dialog(
    title, path, @native_ffi.proton_window_begin_open_file_dialog_ffi,
  )
}

///|
pub fn WindowRef::begin_save_file_dialog(
  self : WindowRef,
  title : String?,
  path : String?,
) -> Int64 raise NativeError {
  self.begin_file_dialog(
    title, path, @native_ffi.proton_window_begin_save_file_dialog_ffi,
  )
}

///|
pub fn WindowRef::begin_choose_directory_dialog(
  self : WindowRef,
  title : String?,
  path : String?,
) -> Int64 raise NativeError {
  self.begin_file_dialog(
    title, path, @native_ffi.proton_window_begin_choose_directory_dialog_ffi,
  )
}

///|
pub fn WindowRef::cancel_dialog(
  self : WindowRef,
  dialog : Int64,
) -> Unit raise NativeError {
  let status = @native_ffi.proton_window_cancel_dialog_ffi(self.handle, dialog)
  if status < 0 {
    raise native_error(status)
  }
}

///|
fn validate_view_config(config : ViewConfig) -> Unit raise NativeError {
  if config.width <= 0 || config.height <= 0 {
    raise invalid_argument("view width and height must be positive")
  }
}

///|
/// Creates a web contents view inside `window`. The view renders above the
/// window's main browser content; use `set_z_order` to stack multiple views.
/// Requires the `web_contents_view` native runtime feature.
pub fn View::View(
  window : Window,
  config : ViewConfig,
) -> View raise NativeError {
  validate_view_config(config)
  let out_view = Ref(@native_ffi.view_null())
  let status = @native_ffi.view_create(
    window.live_handle(),
    config.x,
    config.y,
    config.width,
    config.height,
    runtime_config_bool(config.visible),
    config.z_order,
    @ffi.to_cstr(config.initial_url),
    runtime_config_string(config.background_color),
    out_view,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    View::{
      handle: out_view.val,
      id: @native_ffi.view_logical_id(out_view.val),
      lifecycle: ViewLive,
    }
  }
}

///|
pub fn View::destroy(self : View) -> Unit raise NativeError {
  match self.lifecycle {
    ViewDestroyed => return
    ViewLive | ViewDestroying => self.lifecycle = ViewDestroying
  }
  let status = @native_ffi.proton_view_destroy_ffi(self.handle)
  if status < 0 {
    raise native_error(status)
  } else {
    self.handle = @native_ffi.view_null()
    self.lifecycle = ViewDestroyed
  }
}

///|
fn View::live_handle(self : View) -> @native_ffi.ViewHandle raise NativeError {
  match self.lifecycle {
    ViewLive => self.handle
    ViewDestroying | ViewDestroyed =>
      raise Status(status=proton_err_invalid_state, message="view is destroyed")
  }
}

///|
/// Returns the stable native handle used to correlate native calls.
pub fn View::id(self : View) -> Int64 {
  match self.lifecycle {
    ViewLive => self.id
    ViewDestroying | ViewDestroyed => proton_invalid_handle
  }
}

///|
/// Moves and resizes the view. `x`/`y` use a top-left origin in the owning
/// window's content coordinate space, matching Electron's `setBounds`.
pub fn View::set_bounds(
  self : View,
  x~ : Int,
  y~ : Int,
  width~ : Int,
  height~ : Int,
) -> Unit raise NativeError {
  if width <= 0 || height <= 0 {
    raise invalid_argument("view width and height must be positive")
  }
  check_status(
    @native_ffi.proton_view_set_bounds_ffi(
      self.live_handle(),
      x,
      y,
      width,
      height,
    ),
  )
}

///|
pub fn View::set_visible(self : View, visible : Bool) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_view_set_visible_ffi(
      self.live_handle(),
      if visible {
        1
      } else {
        0
      },
    ),
  )
}

///|
/// Stacks the view relative to the window's other views; higher `z_order`
/// renders above lower values, and views always render above the window's
/// main browser content.
pub fn View::set_z_order(self : View, z_order : Int) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_view_set_z_order_ffi(self.live_handle(), z_order),
  )
}

///|
pub fn View::load_url(self : View, url : String) -> Unit raise NativeError {
  if url.is_empty() {
    raise invalid_argument("url must not be empty")
  }
  check_status(
    @native_ffi.proton_view_load_url_ffi(self.live_handle(), @ffi.to_cstr(url)),
  )
}

///|
/// Reads the current view state from the native runtime.
pub fn View::state(self : View) -> ViewState raise NativeError {
  let fields = FixedArray::make(proton_view_state_field_count, 0)
  check_status(
    @native_ffi.proton_view_get_state_ffi(
      self.live_handle(),
      fields,
      fields.length(),
    ),
  )
  {
    x: fields[0],
    y: fields[1],
    width: fields[2],
    height: fields[3],
    visible: fields[4] != 0,
    z_order: fields[5],
  }
}

///|
/// Returns whether this view has backward and forward history.
pub fn View::navigation_state(self : View) -> (Bool, Bool) raise NativeError {
  let can_go_back : Ref[Int] = { val: 0, }
  let can_go_forward : Ref[Int] = { val: 0, }
  check_status(
    @native_ffi.proton_view_get_navigation_state_ffi(
      self.live_handle(),
      can_go_back,
      can_go_forward,
    ),
  )
  (can_go_back.val != 0, can_go_forward.val != 0)
}

///|
/// Executes JavaScript in the view's main frame without awaiting a result.
pub fn View::eval(self : View, script : String) -> Unit raise NativeError {
  check_status(
    @native_ffi.proton_view_eval_ffi(self.live_handle(), @ffi.to_cstr(script)),
  )
}

///|
/// Sends a browser control command to the view: `back`, `forward`, `reload`,
/// `reload_ignore_cache`, `stop`, `open_devtools`, or `close_devtools`.
pub fn View::browser_command(
  self : View,
  command : String,
  download_id? : Int,
) -> Unit raise NativeError {
  let fields : Map[String, Json] = { "command": command }
  match download_id {
    Some(download_id) =>
      fields["download_id"] = Json::number(
        download_id.to_double(),
        repr=download_id.to_string(),
      )
    None => ()
  }
  check_status(
    @native_ffi.proton_view_browser_command_json_ffi(
      self.live_handle(),
      @ffi.to_cstr(Json::object(fields).stringify()),
    ),
  )
}
