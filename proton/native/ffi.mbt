///|
let proton_process_handled = 1

///|
let proton_event_none = 2

///|
let proton_err_buffer_too_small = -11

///|
pub let runtime_wait_none : Int = 0

///|
pub let runtime_wait_event : Int = 1

///|
pub let runtime_wait_bridge : Int = 2

///|
pub let runtime_wait_platform : Int = 4

///|
pub let runtime_wait_all : Int = runtime_wait_event
  .lor(runtime_wait_bridge)
  .lor(runtime_wait_platform)

///|
let proton_invalid_handle : Int64 = 0L

///|
extern "C" fn proton_abi_version_ffi() -> Int = "proton_abi_version"

///|
#borrow(buffer, out_required_len)
extern "C" fn proton_runtime_info_json_ffi(
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_runtime_info_json"

///|
#borrow(config_json, out_exit_code)
extern "C" fn proton_execute_process_ffi(
  config_json : Bytes,
  out_exit_code : Ref[Int],
) -> Int = "proton_execute_process"

///|
#borrow(config_json)
extern "C" fn proton_runtime_probe_json_ffi(config_json : Bytes) -> Int = "proton_runtime_probe_json"

///|
#borrow(config_json, out_runtime)
extern "C" fn proton_runtime_create_json_ffi(
  config_json : Bytes,
  out_runtime : Ref[Int64],
) -> Int = "proton_runtime_create_json"

///|
extern "C" fn proton_runtime_destroy_ffi(runtime : Int64) -> Int = "proton_runtime_destroy"

///|
extern "C" fn proton_runtime_run_ffi(runtime : Int64) -> Int = "proton_runtime_run"

///|
extern "C" fn proton_runtime_quit_ffi(runtime : Int64) -> Int = "proton_runtime_quit"

///|
extern "C" fn proton_runtime_do_message_loop_work_ffi(runtime : Int64) -> Int = "proton_runtime_do_message_loop_work"

///|
#borrow(out_ready_mask)
extern "C" fn proton_runtime_wait_ffi(
  runtime : Int64,
  interest_mask : Int,
  timeout_ms : Int,
  out_ready_mask : Ref[Int],
) -> Int = "proton_runtime_wait"

///|
#borrow(menu_json)
extern "C" fn proton_runtime_set_menu_json_ffi(
  runtime : Int64,
  menu_json : Bytes,
) -> Int = "proton_runtime_set_menu_json"

///|
#borrow(buffer, out_required_len)
extern "C" fn proton_runtime_poll_event_json_ffi(
  runtime : Int64,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_runtime_poll_event_json"

///|
#borrow(buffer, out_required_len)
extern "C" fn proton_runtime_poll_bridge_request_json_ffi(
  runtime : Int64,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_runtime_poll_bridge_request_json"

///|
#borrow(response_json)
extern "C" fn proton_runtime_respond_bridge_request_json_ffi(
  runtime : Int64,
  response_json : Bytes,
) -> Int = "proton_runtime_respond_bridge_request_json"

///|
#borrow(title, message, out_dialog)
extern "C" fn proton_runtime_begin_message_dialog_ffi(
  runtime : Int64,
  title : Bytes,
  title_len : Int,
  message : Bytes,
  message_len : Int,
  level : Int,
  out_dialog : Ref[Int64],
) -> Int = "proton_runtime_begin_message_dialog"

///|
#borrow(buffer, out_required_len)
extern "C" fn proton_runtime_poll_dialog_result_ffi(
  runtime : Int64,
  dialog : Int64,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_runtime_poll_dialog_result"

///|
#borrow(config_json, out_window)
extern "C" fn proton_window_create_json_ffi(
  runtime : Int64,
  config_json : Bytes,
  out_window : Ref[Int64],
) -> Int = "proton_window_create_json"

///|
extern "C" fn proton_window_destroy_ffi(window : Int64) -> Int = "proton_window_destroy"

///|
extern "C" fn proton_window_show_ffi(window : Int64) -> Int = "proton_window_show"

///|
extern "C" fn proton_window_hide_ffi(window : Int64) -> Int = "proton_window_hide"

///|
extern "C" fn proton_window_close_ffi(window : Int64) -> Int = "proton_window_close"

///|
extern "C" fn proton_window_focus_ffi(window : Int64) -> Int = "proton_window_focus"

///|
#borrow(title)
extern "C" fn proton_window_set_title_ffi(window : Int64, title : Bytes) -> Int = "proton_window_set_title"

///|
extern "C" fn proton_window_set_size_ffi(
  window : Int64,
  width : Int,
  height : Int,
) -> Int = "proton_window_set_size"

///|
#borrow(url)
extern "C" fn proton_window_load_url_ffi(window : Int64, url : Bytes) -> Int = "proton_window_load_url"

///|
#borrow(html, base_url)
extern "C" fn proton_window_load_html_ffi(
  window : Int64,
  html : Bytes,
  base_url : Bytes,
) -> Int = "proton_window_load_html"

///|
#borrow(script)
extern "C" fn proton_window_eval_ffi(window : Int64, script : Bytes) -> Int = "proton_window_eval"

///|
#borrow(event_json)
extern "C" fn proton_window_emit_bridge_event_json_ffi(
  window : Int64,
  event_json : Bytes,
) -> Int = "proton_window_emit_bridge_event_json"

///|
#borrow(buffer, out_required_len)
extern "C" fn proton_window_bridge_state_json_ffi(
  window : Int64,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_window_bridge_state_json"

///|
#borrow(buffer, out_required_len)
extern "C" fn proton_window_take_bridge_failure_json_ffi(
  window : Int64,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_window_take_bridge_failure_json"

///|
#borrow(title, message, out_dialog)
extern "C" fn proton_window_begin_message_dialog_ffi(
  window : Int64,
  title : Bytes,
  title_len : Int,
  message : Bytes,
  message_len : Int,
  level : Int,
  out_dialog : Ref[Int64],
) -> Int = "proton_window_begin_message_dialog"

///|
#borrow(title, message, out_dialog)
extern "C" fn proton_window_begin_confirm_dialog_ffi(
  window : Int64,
  title : Bytes,
  title_len : Int,
  message : Bytes,
  message_len : Int,
  level : Int,
  out_dialog : Ref[Int64],
) -> Int = "proton_window_begin_confirm_dialog"

///|
#borrow(title, path, out_dialog)
extern "C" fn proton_window_begin_open_file_dialog_ffi(
  window : Int64,
  title : Bytes,
  title_len : Int,
  path : Bytes,
  path_len : Int,
  out_dialog : Ref[Int64],
) -> Int = "proton_window_begin_open_file_dialog"

///|
#borrow(title, path, out_dialog)
extern "C" fn proton_window_begin_save_file_dialog_ffi(
  window : Int64,
  title : Bytes,
  title_len : Int,
  path : Bytes,
  path_len : Int,
  out_dialog : Ref[Int64],
) -> Int = "proton_window_begin_save_file_dialog"

///|
#borrow(title, path, out_dialog)
extern "C" fn proton_window_begin_choose_directory_dialog_ffi(
  window : Int64,
  title : Bytes,
  title_len : Int,
  path : Bytes,
  path_len : Int,
  out_dialog : Ref[Int64],
) -> Int = "proton_window_begin_choose_directory_dialog"

///|
#borrow(buffer, out_required_len)
extern "C" fn proton_window_poll_dialog_result_ffi(
  window : Int64,
  dialog : Int64,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_window_poll_dialog_result"

///|
#borrow(buffer)
extern "C" fn proton_last_error_message_ffi(
  buffer : FixedArray[Byte],
  buffer_len : Int,
) -> Int = "proton_last_error_message"
