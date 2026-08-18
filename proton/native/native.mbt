///|
pub fn abi_version() -> Int {
  proton_abi_version_ffi()
}

///|
pub fn runtime_info_json() -> String raise NativeError {
  require_native_text("runtime info JSON", PayloadBytesExcludingTerminator, (
    buffer,
    buffer_len,
    required,
  ) => proton_runtime_info_json_ffi(buffer, buffer_len, required))
}

///|
fn decode_runtime_info(text : String) -> RuntimeInfo raise NativeError {
  let json = @json.parse(text) catch {
    error =>
      raise InvalidPayload(
        context="runtime info JSON",
        message=error.to_string(),
      )
  }
  let info : RuntimeInfo = @json.from_json(json) catch {
    error =>
      raise InvalidPayload(context="runtime info", message=error.to_string())
  }
  expect_abi_version(info.abi_version, "runtime info")
  info
}

///|
pub fn runtime_info() -> RuntimeInfo raise NativeError {
  decode_runtime_info(runtime_info_json())
}

///|
/// Returns the operating system's preferred language tags in preference order.
///
/// Platform adapters may return platform-native locale syntax. The public
/// facade owns validation and canonicalization into `Locale` values.
pub fn system_preferred_language_tags() -> Array[String] raise NativeError {
  let text = require_native_text(
    "system preferred languages",
    PayloadBytesExcludingTerminator,
    (buffer, buffer_len, required) => {
      proton_system_preferred_languages_json_ffi(buffer, buffer_len, required)
    },
  )
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
  let text = require_native_text(
    "screen enumeration",
    PayloadBytesExcludingTerminator,
    (buffer, buffer_len, required) => {
      proton_screen_enumerate_json_ffi(buffer, buffer_len, required)
    },
  )
  let json = decode_native_json(text, "screen enumeration")
  @json.from_json(json) catch {
    error =>
      raise InvalidPayload(
        context="screen enumeration",
        message=error.to_string(),
      )
  }
}

///|
pub fn AppActivation::new(
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
  let status = proton_app_instance_acquire_ffi(
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
    proton_app_instance_attach_runtime_ffi(self.handle, runtime.active_handle()),
  )
}

///|
pub fn AppInstance::destroy(self : AppInstance) -> Unit raise NativeError {
  if self.destroyed {
    return
  }
  check_status(proton_app_instance_destroy_ffi(self.handle))
  self.handle = proton_invalid_handle
  self.destroyed = true
}

///|
pub fn last_error_message() -> String {
  let required = proton_last_error_message_ffi(FixedArray::make(1, b'\x00'), 0)
  if required <= 0 {
    return ""
  }
  let buffer = FixedArray::make(required + 1, b'\x00')
  let _ = proton_last_error_message_ffi(buffer, buffer.length())
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
  match config.raw_json {
    Some(_) => ()
    None =>
      if config.width <= 0 || config.height <= 0 {
        raise invalid_argument("width and height must be positive")
      }
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
fn decode_int_json(json : Json, label : String) -> Int raise NativeError {
  @json.from_json(json) catch {
    error =>
      raise InvalidPayload(
        context=label,
        message="expected integer: " + error.to_string(),
      )
  }
}

///|
fn decode_bool_json(json : Json, label : String) -> Bool raise NativeError {
  @json.from_json(json) catch {
    error =>
      raise InvalidPayload(
        context=label,
        message="expected boolean: " + error.to_string(),
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
fn decode_runtime_event_json(text : String) -> RuntimeEvent raise NativeError {
  let json = decode_native_json(text, "runtime event")
  let object = match json {
    Object(object) => object
    _ =>
      raise InvalidPayload(context="runtime event", message="expected object")
  }
  decode_optional_abi_version(object, "runtime event")
  guard object
    is {
      "type": event_type_json,
      "window"? : window_json,
      "view"? : view_json,
      "title"? : title_json,
      "is_loading"? : is_loading_json,
      "state"? : state_json,
      "request_id"? : request_id_json,
      "url"? : url_json,
      "method"? : method_json,
      "user_gesture"? : user_gesture_json,
      "redirect"? : redirect_json,
      "disposition"? : disposition_json,
      "download_id"? : download_id_json,
      "suggested_name"? : suggested_name_json,
      "download_state"? : download_state_json,
      "received_bytes"? : received_bytes_json,
      "total_bytes"? : total_bytes_json,
      "percent"? : percent_json,
      "error"? : error_json,
      "permissions"? : permissions_json,
      "command_id"? : command_id_json,
      "revision"? : revision_json,
      "items"? : items_json,
      "ok"? : ok_json,
      "message"? : message_json,
      ..
    } else {
    raise InvalidPayload(context="runtime event", message="missing type")
  }
  let event_type = decode_string_json(event_type_json, "runtime event type")
  let window = window_json.map(value => {
    decode_int64_json(value, "runtime event window")
  })
  let view = view_json.map(value => {
    decode_int64_json(value, "runtime event view")
  })
  let title = title_json.map(value => {
    decode_string_json(value, "runtime event title")
  })
  let is_loading = is_loading_json.map(value => {
    decode_bool_json(value, "runtime event is_loading")
  })
  let state = match state_json {
    None => None
    Some(value) =>
      Some(
        @json.from_json(value) catch {
          error =>
            raise InvalidPayload(
              context="runtime event window state",
              message=error.to_string(),
            )
        },
      )
  }
  let request_id = request_id_json.map(value => {
    decode_int64_json(value, "runtime event request id")
  })
  let url = url_json.map(value => decode_string_json(value, "runtime event URL"))
  let http_method = method_json.map(value => {
    decode_string_json(value, "runtime event method")
  })
  let user_gesture = user_gesture_json.map(value => {
    decode_bool_json(value, "runtime event user gesture")
  })
  let redirect = redirect_json.map(value => {
    decode_bool_json(value, "runtime event redirect")
  })
  let disposition = disposition_json.map(value => {
    decode_int_json(value, "runtime event disposition")
  })
  let download_id = download_id_json.map(value => {
    decode_int_json(value, "runtime event download id")
  })
  let suggested_name = suggested_name_json.map(value => {
    decode_string_json(value, "runtime event suggested name")
  })
  let download_state = download_state_json.map(value => {
    decode_string_json(value, "runtime event download state")
  })
  let received_bytes = received_bytes_json.map(value => {
    decode_int64_json(value, "runtime event received bytes")
  })
  let total_bytes = total_bytes_json.map(value => {
    decode_int64_json(value, "runtime event total bytes")
  })
  let percent = percent_json.map(value => {
    decode_int_json(value, "runtime event percent")
  })
  let error_code = error_json.map(value => {
    decode_int_json(value, "runtime event error code")
  })
  let permissions = permissions_json.map(value => {
    decode_int_json(value, "runtime event permissions")
  })
  let menu_command_id = command_id_json.map(value => {
    decode_string_json(value, "runtime event command id")
  })
  let revision = revision_json.map(value => {
    decode_int64_json(value, "runtime event revision")
  })
  let items = match items_json {
    None => []
    Some(Array(values)) => {
      let items : Array[String] = []
      for value in values {
        items.push(decode_string_json(value, "runtime event item"))
      }
      items
    }
    Some(_) =>
      raise InvalidPayload(
        context="runtime event items",
        message="expected string array",
      )
  }
  let ok = match ok_json {
    None => None
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(_) =>
      raise InvalidPayload(
        context="runtime event ok",
        message="expected boolean",
      )
  }
  let message = message_json.map(value => {
    decode_string_json(value, "runtime event message")
  })
  RuntimeEvent::{
    event_type,
    window,
    view,
    title,
    is_loading,
    state,
    request_id,
    url,
    http_method,
    user_gesture,
    redirect,
    disposition,
    download_id,
    suggested_name,
    download_state,
    received_bytes,
    total_bytes,
    percent,
    error_code,
    permissions,
    menu_command_id,
    revision,
    items,
    ok,
    message,
  }
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
pub fn execute_process(
  config? : RuntimeConfig = RuntimeConfig::new(),
) -> ProcessResult raise NativeError {
  let out_exit_code = Ref(0)
  let status = proton_execute_process_ffi(
    @ffi.to_cstr(config.to_json_string()),
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
pub fn probe_runtime(
  config? : RuntimeConfig = RuntimeConfig::new(),
) -> Unit raise NativeError {
  check_status(
    proton_runtime_probe_json_ffi(@ffi.to_cstr(config.to_json_string())),
  )
}

///|
pub fn RuntimeConfig::probe(self : RuntimeConfig) -> Unit raise NativeError {
  probe_runtime(config=self)
}

///|
pub fn Runtime::new(
  config? : RuntimeConfig = RuntimeConfig::new(),
) -> Runtime raise NativeError {
  let out_runtime = Ref(proton_invalid_handle)
  let status = proton_runtime_create_json_ffi(
    @ffi.to_cstr(config.to_json_string()),
    out_runtime,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    Runtime::{ handle: out_runtime.val, lifecycle: RuntimeActive }
  }
}

///|
pub fn Runtime::destroy(self : Runtime) -> Unit raise NativeError {
  match self.lifecycle {
    RuntimeDestroyed => return
    RuntimeActive | RuntimeDestroying => self.lifecycle = RuntimeDestroying
  }
  let status = proton_runtime_destroy_ffi(self.handle)
  if status < 0 {
    raise native_error(status)
  } else {
    self.handle = proton_invalid_handle
    self.lifecycle = RuntimeDestroyed
  }
}

///|
fn Runtime::active_handle(self : Runtime) -> Int64 raise NativeError {
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
/// Advances one external-message-pump iteration for a low-level host.
pub fn Runtime::do_message_loop_work(self : Runtime) -> Unit raise NativeError {
  check_status(proton_runtime_do_message_loop_work_ffi(self.active_handle()))
}

///|
/// Waits for low-level external-pump work.
pub fn Runtime::wait(
  self : Runtime,
  interest_mask~ : Int,
  timeout_ms? : Int,
) -> RuntimeWaitReady raise NativeError {
  if interest_mask == runtime_wait_none {
    raise invalid_argument("interest_mask is required")
  }
  if interest_mask.land(runtime_wait_all.lnot()) != 0 {
    raise invalid_argument("interest_mask contains unsupported bits")
  }
  let ready_mask = Ref(runtime_wait_none)
  let status = proton_runtime_wait_ffi(
    self.active_handle(),
    interest_mask,
    encode_wait_timeout(timeout_ms),
    ready_mask,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    RuntimeWaitReady::{ mask: ready_mask.val }
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
  check_status(proton_host_loop_begin_ffi())
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
  let status = proton_host_loop_poll_ffi(
    encode_wait_timeout(timeout_ms),
    ready_mask,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    RuntimeWaitReady::{ mask: ready_mask.val }
  }
}

///|
/// Releases the host loop. Safe to call when no loop is running.
pub fn host_loop_end() -> Unit {
  proton_host_loop_end_ffi()
}

///|
/// Wakes a blocked `Runtime::wait` or `host_loop_poll`, or makes the next one
/// return immediately when none is blocked yet. A lost wakeup deadlocks the
/// host, so the two cases behave the same.
///
/// Takes no runtime and is safe from any thread, touching only atomics and the
/// platform run loop. That is what lets a thread outside the runtime call it:
/// handles validate thread ownership and such a thread owns none.
pub fn signal_wakeup() -> Unit {
  proton_runtime_signal_wakeup_ffi()
}

///|
/// Installs the write end of a non-blocking pipe used to wake the host async
/// runtime. The native runtime duplicates the descriptor and does not borrow
/// the caller's ownership.
pub fn Runtime::set_wakeup_fd(
  self : Runtime,
  wakeup_fd : Int,
) -> Unit raise NativeError {
  if wakeup_fd < -1 {
    raise invalid_argument("wakeup_fd must be -1 or a valid descriptor")
  }
  check_status(
    proton_runtime_set_wakeup_fd_ffi(self.active_handle(), wakeup_fd),
  )
}

///|
/// Prepares a platform-owned wakeup source and returns its locator.
///
/// Call `activate_wakeup_source` after opening the locator for reading.
pub fn Runtime::prepare_wakeup_source(
  self : Runtime,
) -> String raise NativeError {
  let handle = self.active_handle()
  require_native_text(
    "runtime wakeup source",
    PayloadBytesExcludingTerminator,
    (buffer, buffer_len, required) => {
      proton_runtime_prepare_wakeup_source_ffi(
        handle, buffer, buffer_len, required,
      )
    },
  )
}

///|
/// Activates a prepared wakeup source after its reader is connected.
pub fn Runtime::activate_wakeup_source(
  self : Runtime,
) -> Unit raise NativeError {
  check_status(proton_runtime_activate_wakeup_source_ffi(self.active_handle()))
}

///|
/// Returns the delay until CEF next needs its external message pump serviced,
/// or `None` when no delayed pump is scheduled.
pub fn Runtime::next_wakeup_delay_ms(self : Runtime) -> Int? raise NativeError {
  let delay = Ref(-1L)
  let status = proton_runtime_next_wakeup_delay_ms_ffi(
    self.active_handle(),
    delay,
  )
  if status < 0 {
    raise native_error(status)
  } else if delay.val < 0L {
    None
  } else if delay.val > 2147483647L {
    Some(2147483647)
  } else {
    Some(delay.val.to_int())
  }
}

///|
/// Replaces the application-level native menu bar for this runtime.
pub fn Runtime::set_menu(
  self : Runtime,
  menu : MenuBar,
) -> Unit raise NativeError {
  check_status(
    proton_runtime_set_menu_json_ffi(
      self.active_handle(),
      @ffi.to_cstr(menu.to_json_string()),
    ),
  )
}

///|
pub fn Runtime::poll_event_json(self : Runtime) -> String? raise NativeError {
  let handle = self.active_handle()
  read_native_text("runtime event JSON", PayloadBytesExcludingTerminator, (
    buffer,
    buffer_len,
    required,
  ) => proton_runtime_poll_event_json_ffi(handle, buffer, buffer_len, required))
}

///|
pub fn Runtime::poll_event(self : Runtime) -> RuntimeEvent? raise NativeError {
  match self.poll_event_json() {
    Some(text) => Some(decode_runtime_event_json(text))
    None => None
  }
}

///|
pub fn Runtime::poll_bridge_request_json(
  self : Runtime,
) -> String? raise NativeError {
  let handle = self.active_handle()
  read_native_text("bridge request JSON", PayloadBytesExcludingTerminator, (
    buffer,
    buffer_len,
    required,
  ) => {
    proton_runtime_poll_bridge_request_json_ffi(
      handle, buffer, buffer_len, required,
    )
  })
}

///|
pub fn Runtime::poll_bridge_request(
  self : Runtime,
) -> BridgeRequest? raise NativeError {
  match self.poll_bridge_request_json() {
    Some(text) => Some(decode_bridge_request_json(text))
    None => None
  }
}

///|
pub fn Runtime::respond_bridge_request(
  self : Runtime,
  response : BridgeResponse,
) -> Unit raise NativeError {
  check_status(
    proton_runtime_respond_bridge_request_json_ffi(
      self.active_handle(),
      @ffi.to_cstr(response.to_json_string()),
    ),
  )
}

///|
pub fn Window::new(
  runtime : Runtime,
  config? : WindowConfig = WindowConfig::new(),
) -> Window raise NativeError {
  validate_window_config(config)
  let out_window = Ref(proton_invalid_handle)
  let status = proton_window_create_json_ffi(
    runtime.active_handle(),
    @ffi.to_cstr(config.to_json_string()),
    out_window,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    Window::{ handle: out_window.val, lifecycle: WindowLive }
  }
}

///|
pub fn Window::destroy(self : Window) -> Unit raise NativeError {
  match self.lifecycle {
    WindowDestroyed => return
    WindowLive | WindowCloseRequested | WindowDestroying =>
      self.lifecycle = WindowDestroying
  }
  let status = proton_window_destroy_ffi(self.handle)
  if status < 0 {
    raise native_error(status)
  } else {
    self.handle = proton_invalid_handle
    self.lifecycle = WindowDestroyed
  }
}

///|
fn Window::live_handle(self : Window) -> Int64 raise NativeError {
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
  check_status(proton_window_show_ffi(self.live_handle()))
}

///|
/// Borrows this owning window handle for APIs that must not destroy it.
pub fn Window::as_ref(self : Window) -> WindowRef {
  WindowRef::unsafe_from_handle(
    match self.lifecycle {
      WindowLive => self.handle
      WindowCloseRequested | WindowDestroying | WindowDestroyed =>
        proton_invalid_handle
    },
  )
}

///|
/// Returns the stable native handle used to correlate runtime events.
pub fn Window::id(self : Window) -> Int64 {
  match self.lifecycle {
    WindowLive | WindowCloseRequested => self.handle
    WindowDestroying | WindowDestroyed => proton_invalid_handle
  }
}

///|
pub fn Window::hide(self : Window) -> Unit raise NativeError {
  check_status(proton_window_hide_ffi(self.live_handle()))
}

///|
pub fn Window::close(self : Window) -> Unit raise NativeError {
  match self.lifecycle {
    WindowCloseRequested | WindowDestroying | WindowDestroyed => return
    WindowLive => ()
  }
  let status = proton_window_close_ffi(self.handle)
  if status < 0 {
    raise native_error(status)
  } else {
    self.lifecycle = WindowCloseRequested
  }
}

///|
pub fn Window::focus(self : Window) -> Unit raise NativeError {
  check_status(proton_window_focus_ffi(self.live_handle()))
}

///|
pub fn Window::set_title(
  self : Window,
  title : String,
) -> Unit raise NativeError {
  check_status(
    proton_window_set_title_ffi(self.live_handle(), @ffi.to_cstr(title)),
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
  check_status(proton_window_set_size_ffi(self.live_handle(), width, height))
}

///|
pub fn Window::minimize(self : Window) -> Unit raise NativeError {
  check_status(proton_window_minimize_ffi(self.live_handle()))
}

///|
pub fn Window::maximize(self : Window) -> Unit raise NativeError {
  check_status(proton_window_maximize_ffi(self.live_handle()))
}

///|
pub fn Window::restore(self : Window) -> Unit raise NativeError {
  check_status(proton_window_restore_ffi(self.live_handle()))
}

///|
pub fn Window::set_fullscreen(
  self : Window,
  fullscreen : Bool,
) -> Unit raise NativeError {
  check_status(
    proton_window_set_fullscreen_ffi(
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
pub fn Window::set_position(
  self : Window,
  x : Int,
  y : Int,
) -> Unit raise NativeError {
  check_status(proton_window_set_position_ffi(self.live_handle(), x, y))
}

///|
pub fn Window::set_always_on_top(
  self : Window,
  always_on_top : Bool,
) -> Unit raise NativeError {
  check_status(
    proton_window_set_always_on_top_ffi(
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
pub fn Window::set_zoom_percent(
  self : Window,
  zoom_percent : Int,
) -> Unit raise NativeError {
  if zoom_percent < 25 || zoom_percent > 500 {
    raise invalid_argument("zoom_percent must be between 25 and 500")
  }
  check_status(
    proton_window_set_zoom_percent_ffi(self.live_handle(), zoom_percent),
  )
}

///|
pub fn Window::state(self : Window) -> WindowState raise NativeError {
  let handle = self.live_handle()
  let text = match
    read_native_text("window state", PayloadBytesExcludingTerminator, (
      buffer,
      buffer_len,
      required,
    ) => proton_window_state_json_ffi(handle, buffer, buffer_len, required)) {
    Some(text) => text
    None =>
      raise InvalidPayload(context="window state", message="missing payload")
  }
  @json.from_json(decode_native_json(text, "window state")) catch {
    error =>
      raise InvalidPayload(context="window state", message=error.to_string())
  }
}

///|
pub fn Window::set_close_interception(
  self : Window,
  enabled : Bool,
) -> Unit raise NativeError {
  check_status(
    proton_window_set_close_interception_ffi(
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
  check_status(
    proton_window_respond_close_request_ffi(
      self.live_handle(),
      request_id,
      if allow {
        1
      } else {
        0
      },
    ),
  )
}

///|
pub fn Window::load_url(self : Window, url : String) -> Unit raise NativeError {
  check_status(
    proton_window_load_url_ffi(self.live_handle(), @ffi.to_cstr(url)),
  )
}

///|
pub fn Window::load_html(
  self : Window,
  html : String,
  base_url : String,
) -> Unit raise NativeError {
  check_status(
    proton_window_load_html_ffi(
      self.live_handle(),
      @ffi.to_cstr(html),
      @ffi.to_cstr(base_url),
    ),
  )
}

///|
/// Load an HTML document whose relative URLs resolve inside `asset_root`.
pub fn Window::load_asset(
  self : Window,
  html : String,
  document_url : String,
  asset_root : String,
) -> Unit raise NativeError {
  check_status(
    proton_window_load_asset_ffi(
      self.live_handle(),
      @ffi.to_cstr(html),
      @ffi.to_cstr(document_url),
      @ffi.to_cstr(asset_root),
    ),
  )
}

///|
pub fn Window::eval(self : Window, script : String) -> Unit raise NativeError {
  check_status(proton_window_eval_ffi(self.live_handle(), @ffi.to_cstr(script)))
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
    proton_window_browser_command_json_ffi(
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
    proton_window_respond_browser_request_json_ffi(
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
    proton_window_emit_bridge_event_json_ffi(
      self.live_handle(),
      @ffi.to_cstr(event_json),
    ),
  )
}

///|
fn window_bridge_json(
  window : Window,
  context : String,
  query : (Int64, FixedArray[Byte], Int, Ref[Int]) -> Int,
) -> String? raise NativeError {
  let handle = window.live_handle()
  read_native_text(context, PayloadBytesExcludingTerminator, (
    buffer,
    buffer_len,
    required,
  ) => query(handle, buffer, buffer_len, required))
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
      self, "bridge lifecycle state", proton_window_bridge_state_json_ffi,
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
      self, "bridge diagnostic", proton_window_take_bridge_failure_json_ffi,
    ) {
    None => None
    Some(text) => Some(decode_bridge_diagnostic(text))
  }
}

///|
/// Begins retrieving cookies for the window's session. If `url` is `None`,
/// all cookies are retrieved; otherwise only cookies matching the URL are
/// returned. When `include_http_only` is `true`, HTTP-only cookies are
/// included. Returns immediately; call `cookie_poll_get` on each message
/// loop iteration until it returns `Some(json)`.
pub fn Window::cookie_begin_get(
  self : Window,
  url : String?,
  include_http_only : Bool,
) -> Unit raise NativeError {
  let url_bytes = match url {
    Some(u) => @ffi.to_cstr(u)
    None => @ffi.to_cstr("")
  }
  check_status(
    proton_window_cookie_begin_get_json_ffi(
      self.live_handle(),
      url_bytes,
      if include_http_only {
        1
      } else {
        0
      },
    ),
  )
}

///|
/// Polls for the result of a cookie get operation. Returns `None` if the
/// operation is still in progress, or `Some(json)` with a JSON array of
/// cookie objects when complete.
pub fn Window::cookie_poll_get(self : Window) -> String? raise NativeError {
  let handle = self.live_handle()
  match
    read_native_text("cookie get", BufferBytesIncludingTerminator, (
      buffer,
      buffer_len,
      required,
    ) => {
      proton_window_cookie_poll_get_json_ffi(
        handle, buffer, buffer_len, required,
      )
    }) {
    None => None
    Some(text) => Some(text)
  }
}

///|
/// Sets a cookie from a JSON object. The JSON must contain "url", "name",
/// and "value", and may contain "domain", "path", "secure", "http_only",
/// "same_site", "expires". Fire-and-forget.
pub fn Window::cookie_set(
  self : Window,
  cookie_json : String,
) -> Unit raise NativeError {
  check_status(
    proton_window_cookie_set_json_ffi(
      self.live_handle(),
      @ffi.to_cstr(cookie_json),
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
    proton_window_cookie_delete_ffi(self.live_handle(), url_bytes, name_bytes),
  )
}

///|
/// Flushes the cookie store to disk. Fire-and-forget.
pub fn Window::cookie_flush(self : Window) -> Unit raise NativeError {
  check_status(proton_window_cookie_flush_ffi(self.live_handle()))
}

///|
/// Clears the HTTP cache for the window's request context. Fire-and-forget.
pub fn Window::clear_cache(self : Window) -> Unit raise NativeError {
  check_status(proton_window_clear_cache_ffi(self.live_handle()))
}

///|
/// Creates an empty native image. Use `add_png`, `add_jpeg`, or `add_bitmap`
/// to add a representation at a given scale factor, then query with `is_empty`
/// or `size`, and export with `to_png`, `to_jpeg`, or `to_bitmap`.
///
/// Raises `UnsupportedNativeFeature` when the native engine is not available.
pub fn NativeImage::create_empty() -> NativeImage raise NativeError {
  let out_image = Ref(proton_invalid_handle)
  check_status(proton_image_create_empty_ffi(out_image))
  NativeImage::{ handle: out_image.val, lifecycle: ImageLive }
}

///|
fn NativeImage::live_handle(self : NativeImage) -> Int64 raise NativeError {
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
  let status = proton_image_destroy_ffi(self.handle)
  self.handle = proton_invalid_handle
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
    proton_image_add_png_ffi(
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
    proton_image_add_jpeg_ffi(
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
    proton_image_add_bitmap_ffi(
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
  let status = proton_image_is_empty_ffi(self.live_handle())
  if status < 0 {
    raise native_error(status)
  }
  status == 1
}

///|
/// Returns the image size in density-independent pixels as `(width, height)`.
pub fn NativeImage::size(self : NativeImage) -> (Int, Int) raise NativeError {
  let handle = self.live_handle()
  let text = require_native_text(
    "image size",
    PayloadBytesExcludingTerminator,
    (buffer, buffer_len, required) => {
      proton_image_get_size_json_ffi(handle, buffer, buffer_len, required)
    },
  )
  let json = decode_native_json(text, "image size")
  let size : ImageSize = @json.from_json(json) catch {
    error =>
      raise InvalidPayload(context="image size", message=error.to_string())
  }
  (size.width, size.height)
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
    proton_image_to_png_ffi(
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
    proton_image_to_jpeg_ffi(
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
    proton_image_to_bitmap_ffi(
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
  let status = proton_window_begin_message_dialog_ffi(
    self.handle,
    title_buffer,
    dialog_text_payload_len(title_buffer),
    message_buffer,
    dialog_text_payload_len(message_buffer),
    level,
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
  let status = proton_runtime_begin_message_dialog_ffi(
    self.active_handle(),
    title_buffer,
    dialog_text_payload_len(title_buffer),
    message_buffer,
    dialog_text_payload_len(message_buffer),
    level,
    dialog,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    dialog.val
  }
}

///|
pub fn Runtime::poll_message_dialog(
  self : Runtime,
  dialog : Int64,
) -> Bool raise NativeError {
  let handle = self.active_handle()
  match
    read_native_text("message dialog result", BufferBytesIncludingTerminator, (
      buffer,
      buffer_len,
      required,
    ) => {
      proton_runtime_poll_dialog_result_ffi(
        handle, dialog, buffer, buffer_len, required,
      )
    }) {
    None => false
    Some(_) => true
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
  let status = proton_window_begin_confirm_dialog_ffi(
    self.handle,
    title_buffer,
    dialog_text_payload_len(title_buffer),
    message_buffer,
    dialog_text_payload_len(message_buffer),
    level,
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
  callback : (Int64, Bytes, Int, Bytes, Int, Ref[Int64]) -> Int,
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
  self.begin_file_dialog(title, path, proton_window_begin_open_file_dialog_ffi)
}

///|
pub fn WindowRef::begin_save_file_dialog(
  self : WindowRef,
  title : String?,
  path : String?,
) -> Int64 raise NativeError {
  self.begin_file_dialog(title, path, proton_window_begin_save_file_dialog_ffi)
}

///|
pub fn WindowRef::begin_choose_directory_dialog(
  self : WindowRef,
  title : String?,
  path : String?,
) -> Int64 raise NativeError {
  self.begin_file_dialog(
    title, path, proton_window_begin_choose_directory_dialog_ffi,
  )
}

///|
pub fn WindowRef::poll_dialog_result(
  self : WindowRef,
  dialog : Int64,
) -> DialogPollResult raise NativeError {
  let handle = self.handle
  match
    read_native_text("window dialog result", BufferBytesIncludingTerminator, (
      buffer,
      buffer_len,
      required,
    ) => {
      proton_window_poll_dialog_result_ffi(
        handle, dialog, buffer, buffer_len, required,
      )
    }) {
    None => Pending
    Some(result) => Ready(result)
  }
}

///|
fn validate_view_config(config : ViewConfig) -> Unit raise NativeError {
  match config.raw_json {
    Some(_) => ()
    None =>
      if config.width <= 0 || config.height <= 0 {
        raise invalid_argument("view width and height must be positive")
      }
  }
}

///|
/// Creates a web contents view inside `window`. The view renders above the
/// window's main browser content; use `set_z_order` to stack multiple views.
/// Requires the `web_contents_view` native runtime feature.
pub fn View::new(
  window : Window,
  config : ViewConfig,
) -> View raise NativeError {
  validate_view_config(config)
  let out_view = Ref(proton_invalid_handle)
  let status = proton_view_create_json_ffi(
    window.live_handle(),
    @ffi.to_cstr(config.to_json_string()),
    out_view,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    View::{ handle: out_view.val, lifecycle: ViewLive }
  }
}

///|
pub fn View::destroy(self : View) -> Unit raise NativeError {
  match self.lifecycle {
    ViewDestroyed => return
    ViewLive | ViewDestroying => self.lifecycle = ViewDestroying
  }
  let status = proton_view_destroy_ffi(self.handle)
  if status < 0 {
    raise native_error(status)
  } else {
    self.handle = proton_invalid_handle
    self.lifecycle = ViewDestroyed
  }
}

///|
fn View::live_handle(self : View) -> Int64 raise NativeError {
  match self.lifecycle {
    ViewLive => self.handle
    ViewDestroying | ViewDestroyed =>
      raise Status(status=proton_err_invalid_state, message="view is destroyed")
  }
}

///|
/// Borrows this view handle for APIs that must not destroy it.
pub fn View::as_ref(self : View) -> ViewRef {
  ViewRef::unsafe_from_handle(
    match self.lifecycle {
      ViewLive => self.handle
      ViewDestroying | ViewDestroyed => proton_invalid_handle
    },
  )
}

///|
/// Returns the stable native handle used to correlate native calls.
pub fn View::id(self : View) -> Int64 {
  match self.lifecycle {
    ViewLive => self.handle
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
    proton_view_set_bounds_ffi(self.live_handle(), x, y, width, height),
  )
}

///|
pub fn View::set_visible(self : View, visible : Bool) -> Unit raise NativeError {
  check_status(
    proton_view_set_visible_ffi(self.live_handle(), if visible { 1 } else { 0 }),
  )
}

///|
/// Stacks the view relative to the window's other views; higher `z_order`
/// renders above lower values, and views always render above the window's
/// main browser content.
pub fn View::set_z_order(self : View, z_order : Int) -> Unit raise NativeError {
  check_status(proton_view_set_z_order_ffi(self.live_handle(), z_order))
}

///|
pub fn View::load_url(self : View, url : String) -> Unit raise NativeError {
  if url.is_empty() {
    raise invalid_argument("url must not be empty")
  }
  check_status(proton_view_load_url_ffi(self.live_handle(), @ffi.to_cstr(url)))
}

///|
/// Reads the current view state from the native runtime.
pub fn View::state(self : View) -> ViewState raise NativeError {
  let handle = self.live_handle()
  let text = match
    read_native_text("view state", PayloadBytesExcludingTerminator, (
      buffer,
      buffer_len,
      required,
    ) => proton_view_state_json_ffi(handle, buffer, buffer_len, required)) {
    Some(text) => text
    None =>
      raise InvalidPayload(context="view state", message="missing payload")
  }
  @json.from_json(decode_native_json(text, "view state")) catch {
    error =>
      raise InvalidPayload(context="view state", message=error.to_string())
  }
}

///|
/// Loads inline HTML into the view, served from `base_url` on the `proton://`
/// scheme, mirroring `Window::load_html`.
pub fn View::load_html(
  self : View,
  html : String,
  base_url : String,
) -> Unit raise NativeError {
  check_status(
    proton_view_load_html_ffi(
      self.live_handle(),
      @ffi.to_cstr(html),
      @ffi.to_cstr(base_url),
    ),
  )
}

///|
/// Executes JavaScript in the view's main frame without awaiting a result.
pub fn View::eval(self : View, script : String) -> Unit raise NativeError {
  check_status(proton_view_eval_ffi(self.live_handle(), @ffi.to_cstr(script)))
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
    proton_view_browser_command_json_ffi(
      self.live_handle(),
      @ffi.to_cstr(Json::object(fields).stringify()),
    ),
  )
}
