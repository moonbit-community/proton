///|
let proton_process_handled = 1

///|
let proton_event_none = 2

///|
let proton_err_buffer_too_small = -11

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
#borrow(bridge_json)
extern "C" fn proton_window_install_bridge_json_ffi(
  window : Int64,
  bridge_json : Bytes,
) -> Int = "proton_window_install_bridge_json"

///|
#borrow(buffer)
extern "C" fn proton_last_error_message_ffi(
  buffer : FixedArray[Byte],
  buffer_len : Int,
) -> Int = "proton_last_error_message"
