///|
pub fn abi_version() -> Int {
  proton_abi_version_ffi()
}

///|
pub fn runtime_info_json() -> String raise NativeError {
  let required = Ref(0)
  let scratch = FixedArray::make(1, b'\x00')
  let status = proton_runtime_info_json_ffi(scratch, 0, required)
  if status != proton_err_buffer_too_small && status < 0 {
    raise native_error(status)
  }
  let buffer = FixedArray::make(required.val + 1, b'\x00')
  let second_status = proton_runtime_info_json_ffi(
    buffer,
    buffer.length(),
    required,
  )
  if second_status < 0 {
    raise native_error(second_status)
  } else {
    @ffi.from_cstr(Bytes::from_array(buffer))
  }
}

///|
pub fn runtime_info() -> RuntimeInfo raise NativeError {
  let text = runtime_info_json()
  let json = @json.parse(text) catch {
    error =>
      raise InvalidPayload(
        context="runtime info JSON",
        message=error.to_string(),
      )
  }
  @json.from_json(json) catch {
    error =>
      raise InvalidPayload(context="runtime info", message=error.to_string())
  }
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
fn decode_runtime_event_json(text : String) -> RuntimeEvent raise NativeError {
  let json = decode_native_json(text, "runtime event")
  let object = match json {
    Object(object) => object
    _ =>
      raise InvalidPayload(context="runtime event", message="expected object")
  }
  let event_type_json = match object.get("type") {
    Some(value) => value
    None =>
      raise InvalidPayload(context="runtime event", message="missing type")
  }
  let event_type = decode_string_json(event_type_json, "runtime event type")
  let window = match object.get("window") {
    None => None
    Some(value) => Some(decode_int64_json(value, "runtime event window"))
  }
  let menu_command_id = match object.get("command_id") {
    None => None
    Some(value) => Some(decode_string_json(value, "runtime event command id"))
  }
  let revision = match object.get("revision") {
    None => None
    Some(value) => Some(decode_int64_json(value, "runtime event revision"))
  }
  RuntimeEvent::{ event_type, window, menu_command_id, revision }
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
  let request_id_json = match object.get("request_id") {
    Some(value) => value
    None =>
      raise InvalidPayload(
        context="bridge request",
        message="missing request_id",
      )
  }
  let window_json = match object.get("window") {
    Some(value) => value
    None =>
      raise InvalidPayload(context="bridge request", message="missing window")
  }
  let op_json = match object.get("op") {
    Some(value) => value
    None => raise InvalidPayload(context="bridge request", message="missing op")
  }
  let payload = object.get("payload").unwrap_or(Json::empty_object())
  let page_instance = match object.get("page_instance") {
    Some(String(value)) => Some(value)
    _ => None
  }
  let request_id = decode_int64_json(request_id_json, "bridge request_id")
  let window = decode_int64_json(window_json, "bridge request window")
  let op = decode_string_json(op_json, "bridge request op")
  BridgeRequest::{ request_id, window, op, payload, page_instance }
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
/// Runs `entry` on Proton's application thread while the caller owns the
/// platform UI loop on runtimes that advertise `managed_app_runner`. Other
/// platforms may execute `entry` inline.
pub fn run_app(entry : FuncRef[() -> Unit]) -> Unit raise NativeError {
  check_status(proton_app_run_ffi(entry))
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
    Runtime::{ handle: out_runtime.val }
  }
}

///|
pub fn Runtime::destroy(self : Runtime) -> Unit raise NativeError {
  if self.handle == proton_invalid_handle {
    return
  }
  let status = proton_runtime_destroy_ffi(self.handle)
  if status < 0 {
    raise native_error(status)
  } else {
    self.handle = proton_invalid_handle
  }
}

///|
/// Runs CEF's message loop for a low-level host.
///
/// Managed application runners own this loop and reject this operation.
pub fn Runtime::run(self : Runtime) -> Unit raise NativeError {
  check_status(proton_runtime_run_ffi(self.handle))
}

///|
/// Advances one external-message-pump iteration for a low-level host.
///
/// Managed application runners own the native message loop and reject this
/// operation.
pub fn Runtime::do_message_loop_work(self : Runtime) -> Unit raise NativeError {
  check_status(proton_runtime_do_message_loop_work_ffi(self.handle))
}

///|
/// Waits for low-level external-pump work.
///
/// Managed application runners use `set_wakeup_fd` instead and reject this
/// operation.
pub fn Runtime::wait(
  self : Runtime,
  interest_mask~ : Int,
  timeout_ms~ : Int,
) -> RuntimeWaitReady raise NativeError {
  if interest_mask == runtime_wait_none {
    raise invalid_argument("interest_mask is required")
  }
  if interest_mask.land(runtime_wait_all.lnot()) != 0 {
    raise invalid_argument("interest_mask contains unsupported bits")
  }
  if timeout_ms < 0 {
    raise invalid_argument("timeout_ms must be non-negative")
  }
  let ready_mask = Ref(runtime_wait_none)
  let status = proton_runtime_wait_ffi(
    self.handle,
    interest_mask,
    timeout_ms,
    ready_mask,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    RuntimeWaitReady::{ mask: ready_mask.val }
  }
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
  check_status(proton_runtime_set_wakeup_fd_ffi(self.handle, wakeup_fd))
}

///|
/// Prepares a platform-owned wakeup source and returns its locator.
///
/// Call `activate_wakeup_source` after opening the locator for reading.
pub fn Runtime::prepare_wakeup_source(
  self : Runtime,
) -> String raise NativeError {
  let required = Ref(0)
  let scratch = FixedArray::make(1, b'\x00')
  let status = proton_runtime_prepare_wakeup_source_ffi(
    self.handle,
    scratch,
    0,
    required,
  )
  if status != proton_err_buffer_too_small && status < 0 {
    raise native_error(status)
  }
  let buffer = FixedArray::make(required.val + 1, b'\x00')
  let second_status = proton_runtime_prepare_wakeup_source_ffi(
    self.handle,
    buffer,
    buffer.length(),
    required,
  )
  if second_status < 0 {
    raise native_error(second_status)
  } else {
    @ffi.from_cstr(Bytes::from_array(buffer))
  }
}

///|
/// Activates a prepared wakeup source after its reader is connected.
pub fn Runtime::activate_wakeup_source(
  self : Runtime,
) -> Unit raise NativeError {
  check_status(proton_runtime_activate_wakeup_source_ffi(self.handle))
}

///|
/// Returns the delay until CEF next needs its external message pump serviced,
/// or `None` when no delayed pump is scheduled.
///
/// Managed application runners own the native message loop and reject this
/// operation.
pub fn Runtime::next_wakeup_delay_ms(self : Runtime) -> Int? raise NativeError {
  let delay = Ref(-1L)
  let status = proton_runtime_next_wakeup_delay_ms_ffi(self.handle, delay)
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
      self.handle,
      @ffi.to_cstr(menu.to_json_string()),
    ),
  )
}

///|
/// Requests that a low-level host's CEF message loop stop.
///
/// Managed application runners own the native message loop and reject this
/// operation. Destroy the runtime to finish a managed application.
pub fn Runtime::quit(self : Runtime) -> Unit raise NativeError {
  check_status(proton_runtime_quit_ffi(self.handle))
}

///|
pub fn Runtime::poll_event_json(self : Runtime) -> String? raise NativeError {
  let required = Ref(0)
  let scratch = FixedArray::make(1, b'\x00')
  let status = proton_runtime_poll_event_json_ffi(
    self.handle,
    scratch,
    0,
    required,
  )
  if status == proton_event_none {
    return None
  }
  if status != proton_err_buffer_too_small && status < 0 {
    raise native_error(status)
  }
  let buffer = FixedArray::make(required.val + 1, b'\x00')
  let second_status = proton_runtime_poll_event_json_ffi(
    self.handle,
    buffer,
    buffer.length(),
    required,
  )
  if second_status < 0 {
    raise native_error(second_status)
  } else {
    Some(@ffi.from_cstr(Bytes::from_array(buffer)))
  }
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
  let required = Ref(0)
  let scratch = FixedArray::make(1, b'\x00')
  let status = proton_runtime_poll_bridge_request_json_ffi(
    self.handle,
    scratch,
    0,
    required,
  )
  if status == proton_event_none {
    return None
  }
  if status != proton_err_buffer_too_small && status < 0 {
    raise native_error(status)
  }
  let buffer = FixedArray::make(required.val + 1, b'\x00')
  let second_status = proton_runtime_poll_bridge_request_json_ffi(
    self.handle,
    buffer,
    buffer.length(),
    required,
  )
  if second_status < 0 {
    raise native_error(second_status)
  } else {
    Some(@ffi.from_cstr(Bytes::from_array(buffer)))
  }
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
      self.handle,
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
    runtime.handle,
    @ffi.to_cstr(config.to_json_string()),
    out_window,
  )
  if status < 0 {
    raise native_error(status)
  } else {
    Window::{ handle: out_window.val }
  }
}

///|
pub fn Window::destroy(self : Window) -> Unit raise NativeError {
  if self.handle == proton_invalid_handle {
    return
  }
  let status = proton_window_destroy_ffi(self.handle)
  if status < 0 {
    raise native_error(status)
  } else {
    self.handle = proton_invalid_handle
  }
}

///|
pub fn Window::show(self : Window) -> Unit raise NativeError {
  check_status(proton_window_show_ffi(self.handle))
}

///|
/// Borrows this owning window handle for APIs that must not destroy it.
pub fn Window::as_ref(self : Window) -> WindowRef {
  WindowRef::unsafe_from_handle(self.handle)
}

///|
pub fn Window::hide(self : Window) -> Unit raise NativeError {
  check_status(proton_window_hide_ffi(self.handle))
}

///|
pub fn Window::close(self : Window) -> Unit raise NativeError {
  if self.handle == proton_invalid_handle {
    return
  }
  let status = proton_window_close_ffi(self.handle)
  if status < 0 {
    raise native_error(status)
  } else {
    self.handle = proton_invalid_handle
  }
}

///|
pub fn Window::focus(self : Window) -> Unit raise NativeError {
  check_status(proton_window_focus_ffi(self.handle))
}

///|
pub fn Window::set_title(
  self : Window,
  title : String,
) -> Unit raise NativeError {
  check_status(proton_window_set_title_ffi(self.handle, @ffi.to_cstr(title)))
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
  check_status(proton_window_set_size_ffi(self.handle, width, height))
}

///|
pub fn Window::load_url(self : Window, url : String) -> Unit raise NativeError {
  check_status(proton_window_load_url_ffi(self.handle, @ffi.to_cstr(url)))
}

///|
pub fn Window::load_html(
  self : Window,
  html : String,
  base_url : String,
) -> Unit raise NativeError {
  check_status(
    proton_window_load_html_ffi(
      self.handle,
      @ffi.to_cstr(html),
      @ffi.to_cstr(base_url),
    ),
  )
}

///|
pub fn Window::eval(self : Window, script : String) -> Unit raise NativeError {
  check_status(proton_window_eval_ffi(self.handle, @ffi.to_cstr(script)))
}

///|
pub fn Window::emit_bridge_event_json(
  self : Window,
  event_json : String,
) -> Unit raise NativeError {
  check_status(
    proton_window_emit_bridge_event_json_ffi(
      self.handle,
      @ffi.to_cstr(event_json),
    ),
  )
}

///|
fn window_bridge_json(
  window : Window,
  query : (Int64, FixedArray[Byte], Int, Ref[Int]) -> Int,
  optional : Bool,
) -> String? raise NativeError {
  let required = Ref(0)
  let scratch = FixedArray::make(1, b'\x00')
  let status = query(window.handle, scratch, 0, required)
  if optional && status == proton_event_none {
    return None
  }
  if status != proton_err_buffer_too_small && status < 0 {
    raise native_error(status)
  }
  let buffer = FixedArray::make(required.val + 1, b'\x00')
  let second_status = query(window.handle, buffer, buffer.length(), required)
  if second_status < 0 {
    raise native_error(second_status)
  } else {
    Some(@ffi.from_cstr(Bytes::from_array(buffer)))
  }
}

///|
pub fn Window::bridge_lifecycle_state(
  self : Window,
) -> BridgeLifecycleState raise NativeError {
  let text = match
    window_bridge_json(self, proton_window_bridge_state_json_ffi, false) {
    Some(text) => text
    None =>
      raise InvalidPayload(
        context="bridge lifecycle state",
        message="missing payload",
      )
  }
  let json = decode_native_json(text, "bridge lifecycle state")
  @json.from_json(json) catch {
    error =>
      raise InvalidPayload(
        context="bridge lifecycle state",
        message=error.to_string(),
      )
  }
}

///|
pub fn Window::take_bridge_failure(
  self : Window,
) -> BridgeDiagnostic? raise NativeError {
  match
    window_bridge_json(self, proton_window_take_bridge_failure_json_ffi, true) {
    None => None
    Some(text) => {
      let json = decode_native_json(text, "bridge diagnostic")
      let diagnostic : BridgeDiagnostic = @json.from_json(json) catch {
        error =>
          raise InvalidPayload(
            context="bridge diagnostic",
            message=error.to_string(),
          )
      }
      Some(diagnostic)
    }
  }
}

///|
fn dialog_level_to_int(level : DialogLevel) -> Int {
  match level {
    Info => 0
    Warning => 1
    Error => 2
  }
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
let dialog_file_result_buffer_bytes = 65536

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
    dialog_level_to_int(level),
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
    self.handle,
    title_buffer,
    dialog_text_payload_len(title_buffer),
    message_buffer,
    dialog_text_payload_len(message_buffer),
    dialog_level_to_int(level),
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
  let required = Ref(0)
  let buffer = FixedArray::make(1, b'\x00')
  let status = proton_runtime_poll_dialog_result_ffi(
    self.handle,
    dialog,
    buffer,
    buffer.length(),
    required,
  )
  if status == proton_event_none {
    false
  } else if status < 0 {
    raise native_error(status)
  } else {
    true
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
    dialog_level_to_int(level),
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
  let required = Ref(0)
  let buffer = FixedArray::make(dialog_file_result_buffer_bytes, b'\x00')
  let status = proton_window_poll_dialog_result_ffi(
    self.handle,
    dialog,
    buffer,
    buffer.length(),
    required,
  )
  if status == proton_event_none {
    Pending
  } else if status < 0 {
    raise native_error(status)
  } else {
    // On success `required` is the payload plus its terminator, and the
    // rest of the fixed buffer is zero fill. Decode exactly that span.
    Ready(@ffi.from_cstr(Bytes::from_array(buffer[0:required.val])))
  }
}
