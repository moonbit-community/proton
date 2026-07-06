///|
pub fn abi_version() -> Int {
  proton_abi_version_ffi()
}

///|
pub fn runtime_info_json() -> Result[String, NativeError] {
  let required = Ref(0)
  let scratch = FixedArray::make(1, b'\x00')
  let status = proton_runtime_info_json_ffi(scratch, 0, required)
  if status != proton_err_buffer_too_small && status < 0 {
    return Err(native_error(status))
  }
  let buffer = FixedArray::make(required.val + 1, b'\x00')
  let second_status = proton_runtime_info_json_ffi(
    buffer,
    buffer.length(),
    required,
  )
  if second_status < 0 {
    Err(native_error(second_status))
  } else {
    Ok(@ffi.from_cstr(Bytes::from_array(buffer)))
  }
}

///|
pub fn runtime_info() -> Result[RuntimeInfo, NativeError] {
  runtime_info_json().bind(fn(text) {
    try @json.parse(text) catch {
      err =>
        Err({
          status: -1,
          message: "failed to parse runtime info JSON: " + err.to_string(),
        })
    } noraise {
      json =>
        try @json.from_json(json) catch {
          err =>
            Err({
              status: -1,
              message: "failed to decode runtime info JSON: " + err.to_string(),
            })
        } noraise {
          info => Ok(info)
        }
    }
  })
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
  { status, message: last_error_message() }
}

///|
fn status_to_result(status : Int) -> Result[Unit, NativeError] {
  if status < 0 {
    Err(native_error(status))
  } else {
    Ok(())
  }
}

///|
fn invalid_argument(message : String) -> NativeError {
  { status: -1, message }
}

///|
fn validate_window_config(config : WindowConfig) -> Result[Unit, NativeError] {
  match config.raw_json {
    Some(_) => Ok(())
    None =>
      if config.width <= 0 || config.height <= 0 {
        Err(invalid_argument("width and height must be positive"))
      } else {
        Ok(())
      }
  }
}

///|
fn decode_native_json(
  text : String,
  label : String,
) -> Result[Json, NativeError] {
  try @json.parse(text) catch {
    err =>
      Err({
        status: -1,
        message: "failed to parse " + label + " JSON: " + err.to_string(),
      })
  } noraise {
    json => Ok(json)
  }
}

///|
fn decode_string_json(
  json : Json,
  label : String,
) -> Result[String, NativeError] {
  try @json.from_json(json) catch {
    err =>
      Err({
        status: -1,
        message: "failed to decode " + label + " as string: " + err.to_string(),
      })
  } noraise {
    value => Ok(value)
  }
}

///|
fn decode_runtime_event_json(
  text : String,
) -> Result[RuntimeEvent, NativeError] {
  decode_native_json(text, "runtime event").bind(fn(json) {
    let object = match json {
      Object(object) => object
      _ =>
        return Err({
          status: -1,
          message: "failed to decode runtime event JSON: expected object",
        })
    }
    let event_type_json = match object.get("type") {
      Some(value) => value
      None =>
        return Err({
          status: -1,
          message: "failed to decode runtime event JSON: missing type",
        })
    }
    decode_string_json(event_type_json, "runtime event type").bind(fn(
      event_type,
    ) {
      let has_window = object.get("window") is Some(_)
      let payload = if object.get("payload") is Some(String(value)) {
        Some(value)
      } else {
        None
      }
      Ok(RuntimeEvent::{ event_type, has_window, payload })
    })
  })
}

///|
fn decode_int64_json(json : Json, label : String) -> Result[Int64, NativeError] {
  try @json.from_json(json) catch {
    err =>
      Err({
        status: -1,
        message: "failed to decode " + label + " as int64: " + err.to_string(),
      })
  } noraise {
    value => Ok(value)
  }
}

///|
fn decode_bridge_request_json(
  text : String,
) -> Result[BridgeRequest, NativeError] {
  decode_native_json(text, "bridge request").bind(fn(json) {
    let object = match json {
      Object(object) => object
      _ =>
        return Err({
          status: -1,
          message: "failed to decode bridge request JSON: expected object",
        })
    }
    let request_id_json = match object.get("request_id") {
      Some(value) => value
      None =>
        return Err({
          status: -1,
          message: "failed to decode bridge request JSON: missing request_id",
        })
    }
    let window_json = match object.get("window") {
      Some(value) => value
      None =>
        return Err({
          status: -1,
          message: "failed to decode bridge request JSON: missing window",
        })
    }
    let op_json = match object.get("op") {
      Some(value) => value
      None =>
        return Err({
          status: -1,
          message: "failed to decode bridge request JSON: missing op",
        })
    }
    let raw_payload = match object.get("payload") {
      Some(value) => value
      None => Json::object({})
    }
    let (payload, page_instance) = decode_bridge_payload_envelope(raw_payload)
    decode_int64_json(request_id_json, "bridge request_id").bind(fn(
      request_id,
    ) {
      decode_int64_json(window_json, "bridge request window").bind(fn(window) {
        decode_string_json(op_json, "bridge request op").map(fn(op) {
          BridgeRequest::{ request_id, window, op, payload, page_instance }
        })
      })
    })
  })
}

///|
fn decode_bridge_payload_envelope(payload : Json) -> (Json, String?) {
  match payload {
    Object(object) =>
      match object.get("__proton_page_instance") {
        Some(String(page_instance)) =>
          (object.get("payload").unwrap_or(Json::null()), Some(page_instance))
        _ => (payload, None)
      }
    _ => (payload, None)
  }
}

///|
pub fn execute_process(
  config? : RuntimeConfig = RuntimeConfig::new(),
) -> Result[ProcessResult, NativeError] {
  let out_exit_code = Ref(0)
  let status = proton_execute_process_ffi(
    @ffi.to_cstr(config.to_json_string()),
    out_exit_code,
  )
  if status < 0 {
    Err(native_error(status))
  } else if status == proton_process_handled {
    Ok(ProcessResult::SubprocessHandled(out_exit_code.val))
  } else {
    Ok(ProcessResult::MainProcess)
  }
}

///|
pub fn probe_runtime(
  config? : RuntimeConfig = RuntimeConfig::new(),
) -> Result[Unit, NativeError] {
  status_to_result(
    proton_runtime_probe_json_ffi(@ffi.to_cstr(config.to_json_string())),
  )
}

///|
pub fn RuntimeConfig::probe(self : RuntimeConfig) -> Result[Unit, NativeError] {
  probe_runtime(config=self)
}

///|
pub fn Runtime::new(
  config? : RuntimeConfig = RuntimeConfig::new(),
) -> Result[Runtime, NativeError] {
  let out_runtime = Ref(proton_invalid_handle)
  let status = proton_runtime_create_json_ffi(
    @ffi.to_cstr(config.to_json_string()),
    out_runtime,
  )
  if status < 0 {
    Err(native_error(status))
  } else {
    Ok(Runtime::{ handle: out_runtime.val })
  }
}

///|
pub fn Runtime::destroy(self : Runtime) -> Result[Unit, NativeError] {
  if self.handle == proton_invalid_handle {
    return Ok(())
  }
  let status = proton_runtime_destroy_ffi(self.handle)
  if status < 0 {
    Err(native_error(status))
  } else {
    self.handle = proton_invalid_handle
    Ok(())
  }
}

///|
pub fn Runtime::run(self : Runtime) -> Result[Unit, NativeError] {
  status_to_result(proton_runtime_run_ffi(self.handle))
}

///|
pub fn Runtime::do_message_loop_work(
  self : Runtime,
) -> Result[Unit, NativeError] {
  status_to_result(proton_runtime_do_message_loop_work_ffi(self.handle))
}

///|
pub fn Runtime::wait(
  self : Runtime,
  interest_mask~ : Int,
  timeout_ms~ : Int,
) -> Result[RuntimeWaitReady, NativeError] {
  if interest_mask == runtime_wait_none {
    return Err(invalid_argument("interest_mask is required"))
  }
  if interest_mask.land(runtime_wait_all.lnot()) != 0 {
    return Err(invalid_argument("interest_mask contains unsupported bits"))
  }
  if timeout_ms < 0 {
    return Err(invalid_argument("timeout_ms must be non-negative"))
  }
  let ready_mask = Ref(runtime_wait_none)
  let status = proton_runtime_wait_ffi(
    self.handle,
    interest_mask,
    timeout_ms,
    ready_mask,
  )
  if status < 0 {
    Err(native_error(status))
  } else {
    Ok(RuntimeWaitReady::{ mask: ready_mask.val })
  }
}

///|
pub fn Runtime::set_menu(
  self : Runtime,
  menu : MenuBar,
) -> Result[Unit, NativeError] {
  status_to_result(
    proton_runtime_set_menu_json_ffi(
      self.handle,
      @ffi.to_cstr(menu.to_json_string()),
    ),
  )
}

///|
pub fn Runtime::quit(self : Runtime) -> Result[Unit, NativeError] {
  status_to_result(proton_runtime_quit_ffi(self.handle))
}

///|
pub fn Runtime::poll_event_json(self : Runtime) -> Result[String?, NativeError] {
  let required = Ref(0)
  let scratch = FixedArray::make(1, b'\x00')
  let status = proton_runtime_poll_event_json_ffi(
    self.handle,
    scratch,
    0,
    required,
  )
  if status == proton_event_none {
    return Ok(None)
  }
  if status != proton_err_buffer_too_small && status < 0 {
    return Err(native_error(status))
  }
  let buffer = FixedArray::make(required.val + 1, b'\x00')
  let second_status = proton_runtime_poll_event_json_ffi(
    self.handle,
    buffer,
    buffer.length(),
    required,
  )
  if second_status < 0 {
    Err(native_error(second_status))
  } else {
    Ok(Some(@ffi.from_cstr(Bytes::from_array(buffer))))
  }
}

///|
pub fn Runtime::poll_event(
  self : Runtime,
) -> Result[RuntimeEvent?, NativeError] {
  self
  .poll_event_json()
  .bind(fn(event_json) {
    match event_json {
      Some(text) =>
        decode_runtime_event_json(text).map(fn(event) { Some(event) })
      None => Ok(None)
    }
  })
}

///|
pub fn Runtime::poll_bridge_request_json(
  self : Runtime,
) -> Result[String?, NativeError] {
  let required = Ref(0)
  let scratch = FixedArray::make(1, b'\x00')
  let status = proton_runtime_poll_bridge_request_json_ffi(
    self.handle,
    scratch,
    0,
    required,
  )
  if status == proton_event_none {
    return Ok(None)
  }
  if status != proton_err_buffer_too_small && status < 0 {
    return Err(native_error(status))
  }
  let buffer = FixedArray::make(required.val + 1, b'\x00')
  let second_status = proton_runtime_poll_bridge_request_json_ffi(
    self.handle,
    buffer,
    buffer.length(),
    required,
  )
  if second_status < 0 {
    Err(native_error(second_status))
  } else {
    Ok(Some(@ffi.from_cstr(Bytes::from_array(buffer))))
  }
}

///|
pub fn Runtime::poll_bridge_request(
  self : Runtime,
) -> Result[BridgeRequest?, NativeError] {
  self
  .poll_bridge_request_json()
  .bind(fn(request_json) {
    match request_json {
      Some(text) =>
        decode_bridge_request_json(text).map(fn(request) { Some(request) })
      None => Ok(None)
    }
  })
}

///|
pub fn Runtime::respond_bridge_request(
  self : Runtime,
  response : BridgeResponse,
) -> Result[Unit, NativeError] {
  status_to_result(
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
) -> Result[Window, NativeError] {
  match validate_window_config(config) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let out_window = Ref(proton_invalid_handle)
  let status = proton_window_create_json_ffi(
    runtime.handle,
    @ffi.to_cstr(config.to_json_string()),
    out_window,
  )
  if status < 0 {
    Err(native_error(status))
  } else {
    Ok(Window::{ handle: out_window.val })
  }
}

///|
pub fn Window::destroy(self : Window) -> Result[Unit, NativeError] {
  if self.handle == proton_invalid_handle {
    return Ok(())
  }
  let status = proton_window_destroy_ffi(self.handle)
  if status < 0 {
    Err(native_error(status))
  } else {
    self.handle = proton_invalid_handle
    Ok(())
  }
}

///|
pub fn Window::show(self : Window) -> Result[Unit, NativeError] {
  status_to_result(proton_window_show_ffi(self.handle))
}

///|
pub fn Window::hide(self : Window) -> Result[Unit, NativeError] {
  status_to_result(proton_window_hide_ffi(self.handle))
}

///|
pub fn Window::close(self : Window) -> Result[Unit, NativeError] {
  if self.handle == proton_invalid_handle {
    return Ok(())
  }
  let status = proton_window_close_ffi(self.handle)
  if status < 0 {
    Err(native_error(status))
  } else {
    self.handle = proton_invalid_handle
    Ok(())
  }
}

///|
pub fn Window::focus(self : Window) -> Result[Unit, NativeError] {
  status_to_result(proton_window_focus_ffi(self.handle))
}

///|
pub fn Window::set_title(
  self : Window,
  title : String,
) -> Result[Unit, NativeError] {
  status_to_result(
    proton_window_set_title_ffi(self.handle, @ffi.to_cstr(title)),
  )
}

///|
pub fn Window::set_size(
  self : Window,
  width : Int,
  height : Int,
) -> Result[Unit, NativeError] {
  if width <= 0 || height <= 0 {
    return Err(invalid_argument("width and height must be positive"))
  }
  status_to_result(proton_window_set_size_ffi(self.handle, width, height))
}

///|
pub fn Window::load_url(
  self : Window,
  url : String,
) -> Result[Unit, NativeError] {
  status_to_result(proton_window_load_url_ffi(self.handle, @ffi.to_cstr(url)))
}

///|
pub fn Window::load_html(
  self : Window,
  html : String,
  base_url : String,
) -> Result[Unit, NativeError] {
  status_to_result(
    proton_window_load_html_ffi(
      self.handle,
      @ffi.to_cstr(html),
      @ffi.to_cstr(base_url),
    ),
  )
}

///|
pub fn Window::load_html_with_assets(
  self : Window,
  html : String,
  base_url : String,
  asset_root : String,
) -> Result[Unit, NativeError] {
  status_to_result(
    proton_window_load_html_with_assets_ffi(
      self.handle,
      @ffi.to_cstr(html),
      @ffi.to_cstr(base_url),
      @ffi.to_cstr(asset_root),
    ),
  )
}

///|
pub fn Window::eval(
  self : Window,
  script : String,
) -> Result[Unit, NativeError] {
  status_to_result(proton_window_eval_ffi(self.handle, @ffi.to_cstr(script)))
}

///|
pub fn Window::install_bridge(
  self : Window,
  config : BridgeConfig,
) -> Result[Unit, NativeError] {
  status_to_result(
    proton_window_install_bridge_json_ffi(
      self.handle,
      @ffi.to_cstr(config.to_json_string()),
    ),
  )
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
/// Posts a system notification (macOS notification center). App-level: no
/// window handle needed. The first call asks the user for permission; a
/// denied permission drops notifications silently. Unsupported off macOS and
/// outside an app bundle.
///
/// `payload` is an opaque string carried on the notification: when the user
/// clicks it, the runtime emits a `notification_clicked` event holding this
/// string (see `RuntimeEvent::notification_click_payload`), and the app's
/// windows are brought forward.
pub fn post_notification(
  title : String?,
  body : String,
  payload? : String,
) -> Result[Unit, NativeError] {
  let title_buffer = optional_dialog_text_buffer(title)
  let body_buffer = @ffi.to_cstr(body)
  let payload_buffer = optional_dialog_text_buffer(payload)
  status_to_result(
    proton_app_post_notification_ffi(
      title_buffer,
      dialog_text_payload_len(title_buffer),
      body_buffer,
      dialog_text_payload_len(body_buffer),
      payload_buffer,
      dialog_text_payload_len(payload_buffer),
    ),
  )
}

///|
fn begin_message_dialog_async(
  window : WindowRef,
  title : String?,
  message : String,
  level : DialogLevel,
) -> Result[Int64, NativeError] {
  let title_buffer = optional_dialog_text_buffer(title)
  let message_buffer = @ffi.to_cstr(message)
  let dialog = Ref(proton_invalid_handle)
  let status = proton_window_begin_message_dialog_ffi(
    window.handle,
    title_buffer,
    dialog_text_payload_len(title_buffer),
    message_buffer,
    dialog_text_payload_len(message_buffer),
    dialog_level_to_int(level),
    dialog,
  )
  if status < 0 {
    Err(native_error(status))
  } else {
    Ok(dialog.val)
  }
}

///|
fn begin_confirm_dialog_async(
  window : WindowRef,
  title : String?,
  message : String,
  level : DialogLevel,
) -> Result[Int64, NativeError] {
  let title_buffer = optional_dialog_text_buffer(title)
  let message_buffer = @ffi.to_cstr(message)
  let dialog = Ref(proton_invalid_handle)
  let status = proton_window_begin_confirm_dialog_ffi(
    window.handle,
    title_buffer,
    dialog_text_payload_len(title_buffer),
    message_buffer,
    dialog_text_payload_len(message_buffer),
    dialog_level_to_int(level),
    dialog,
  )
  if status < 0 {
    Err(native_error(status))
  } else {
    Ok(dialog.val)
  }
}

///|
fn begin_file_dialog_async(
  window : WindowRef,
  title : String?,
  path : String?,
  callback : (Int64, Bytes, Int, Bytes, Int, Ref[Int64]) -> Int,
) -> Result[Int64, NativeError] {
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
    Err(native_error(status))
  } else {
    Ok(dialog.val)
  }
}

///|
async fn poll_dialog_result(
  window : WindowRef,
  dialog : Int64,
) -> Result[String, NativeError] {
  let required = Ref(0)
  let buffer = FixedArray::make(dialog_file_result_buffer_bytes, b'\x00')
  while true {
    let status = proton_window_poll_dialog_result_ffi(
      window.handle,
      dialog,
      buffer,
      buffer.length(),
      required,
    )
    if status == proton_event_none {
      @async.sleep(1)
    } else if status < 0 {
      return Err(native_error(status))
    } else {
      // On success `required` is the payload plus its terminator, and the
      // rest of the fixed buffer is zero fill. Decode exactly that span —
      // from_cstr only strips the final byte, so handing it the whole buffer
      // would keep ~64K interior NULs in the result string.
      return Ok(@ffi.from_cstr(Bytes::from_array(buffer[0:required.val])))
    }
  }
  Err(invalid_argument("dialog polling exited unexpectedly"))
}

///|
pub async fn show_message_dialog_async(
  window : WindowRef,
  title : String?,
  message : String,
  level : DialogLevel,
) -> Result[Unit, NativeError] {
  match begin_message_dialog_async(window, title, message, level) {
    Err(error) => Err(error)
    Ok(dialog) => poll_dialog_result(window, dialog).map(fn(_) { () })
  }
}

///|
pub async fn show_confirm_dialog_async(
  window : WindowRef,
  title : String?,
  message : String,
  level : DialogLevel,
) -> Result[Bool, NativeError] {
  match begin_confirm_dialog_async(window, title, message, level) {
    Err(error) => Err(error)
    Ok(dialog) =>
      poll_dialog_result(window, dialog).map(fn(result) { result == "1" })
  }
}

///|
pub async fn open_file_dialog_async(
  window : WindowRef,
  title : String?,
  path : String?,
) -> Result[String?, NativeError] {
  match
    begin_file_dialog_async(
      window, title, path, proton_window_begin_open_file_dialog_ffi,
    ) {
    Err(error) => Err(error)
    Ok(dialog) =>
      poll_dialog_result(window, dialog).map(fn(result) {
        if result.is_empty() {
          None
        } else {
          Some(result)
        }
      })
  }
}

///|
pub async fn save_file_dialog_async(
  window : WindowRef,
  title : String?,
  path : String?,
) -> Result[String?, NativeError] {
  match
    begin_file_dialog_async(
      window, title, path, proton_window_begin_save_file_dialog_ffi,
    ) {
    Err(error) => Err(error)
    Ok(dialog) =>
      poll_dialog_result(window, dialog).map(fn(result) {
        if result.is_empty() {
          None
        } else {
          Some(result)
        }
      })
  }
}

///|
pub async fn choose_directory_dialog_async(
  window : WindowRef,
  title : String?,
  path : String?,
) -> Result[String?, NativeError] {
  match
    begin_file_dialog_async(
      window, title, path, proton_window_begin_choose_directory_dialog_ffi,
    ) {
    Err(error) => Err(error)
    Ok(dialog) =>
      poll_dialog_result(window, dialog).map(fn(result) {
        if result.is_empty() {
          None
        } else {
          Some(result)
        }
      })
  }
}
