///|
pub fn ensure_cef_loader_linked() -> Unit {
  @cef_loader.ensure_linked()
}

///|
#external
pub type RuntimeHandle

///|
#external
pub type WindowHandle

///|
#external
pub type ViewHandle

///|
#external
pub type ImageHandle

///|
pub extern "C" fn runtime_null() -> RuntimeHandle = "proton_runtime_null"

///|
pub extern "C" fn window_null() -> WindowHandle = "proton_window_null"

///|
pub extern "C" fn view_null() -> ViewHandle = "proton_view_null"

///|
pub extern "C" fn image_null() -> ImageHandle = "proton_image_null"

///|
pub extern "C" fn window_logical_id(window : WindowHandle) -> Int64 = "proton_window_logical_id"

///|
pub extern "C" fn view_logical_id(view : ViewHandle) -> Int64 = "proton_view_logical_id"

///|
pub extern "C" fn proton_abi_version_ffi() -> Int = "proton_abi_version"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_runtime_info_json_ffi(
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_runtime_info_json"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_system_preferred_languages_json_ffi(
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_system_preferred_languages_json"

///|
#borrow(identifier, activation_json, out_instance, out_primary)
pub extern "C" fn proton_app_instance_acquire_ffi(
  identifier : Bytes,
  activation_json : Bytes,
  out_instance : Ref[Int64],
  out_primary : Ref[Int],
) -> Int = "proton_app_instance_acquire"

///|
pub extern "C" fn proton_app_instance_attach_runtime_ffi(
  instance : Int64,
  runtime : RuntimeHandle,
) -> Int = "proton_app_instance_attach_runtime"

///|
pub extern "C" fn proton_app_instance_destroy_ffi(instance : Int64) -> Int = "proton_app_instance_destroy"

///|
#borrow(runtime_root, helper_path, resources_dir, locales_dir, cache_dir, locale, accept_languages, dialog_ok_label, dialog_cancel_label, out_exit_code)
pub extern "C" fn execute_process(
  use_bundled : Int,
  runtime_root : Bytes,
  helper_path : Bytes,
  resources_dir : Bytes,
  locales_dir : Bytes,
  cache_dir : Bytes,
  locale : Bytes,
  accept_languages : Bytes,
  dialog_ok_label : Bytes,
  dialog_cancel_label : Bytes,
  remote_debugging_port : Int,
  headless : Int,
  persist_session_cookies : Int,
  out_exit_code : Ref[Int],
) -> Int = "proton_internal_execute_process"

///|
#borrow(runtime_root, helper_path, resources_dir, locales_dir, cache_dir, locale, accept_languages, dialog_ok_label, dialog_cancel_label)
pub extern "C" fn runtime_probe(
  use_bundled : Int,
  runtime_root : Bytes,
  helper_path : Bytes,
  resources_dir : Bytes,
  locales_dir : Bytes,
  cache_dir : Bytes,
  locale : Bytes,
  accept_languages : Bytes,
  dialog_ok_label : Bytes,
  dialog_cancel_label : Bytes,
  remote_debugging_port : Int,
  headless : Int,
  persist_session_cookies : Int,
) -> Int = "proton_internal_runtime_probe"

///|
#borrow(runtime_root, helper_path, resources_dir, locales_dir, cache_dir, locale, accept_languages, dialog_ok_label, dialog_cancel_label, out_runtime)
pub extern "C" fn runtime_create(
  use_bundled : Int,
  runtime_root : Bytes,
  helper_path : Bytes,
  resources_dir : Bytes,
  locales_dir : Bytes,
  cache_dir : Bytes,
  locale : Bytes,
  accept_languages : Bytes,
  dialog_ok_label : Bytes,
  dialog_cancel_label : Bytes,
  remote_debugging_port : Int,
  headless : Int,
  persist_session_cookies : Int,
  out_runtime : Ref[RuntimeHandle],
) -> Int = "proton_internal_runtime_create"

///|
pub extern "C" fn proton_runtime_destroy_ffi(runtime : RuntimeHandle) -> Int = "proton_runtime_destroy"

///|
pub extern "C" fn proton_runtime_do_message_loop_work_ffi(
  runtime : RuntimeHandle,
) -> Int = "proton_runtime_do_message_loop_work"

///|
/// `timeout_ms` is `runtime_wait_timeout_infinite` to wait indefinitely; every
/// other negative value is rejected by the native side.
#borrow(out_ready_mask)
pub extern "C" fn proton_runtime_wait_ffi(
  runtime : RuntimeHandle,
  interest_mask : Int,
  timeout_ms : Int,
  out_ready_mask : Ref[Int],
) -> Int = "proton_runtime_wait"

///|
/// Wakes a blocked `Runtime::wait`, or makes the next one return immediately.
///
/// Safe to call from any thread and takes no handle, which is what lets a
/// foreign thread use it: handles validate thread ownership and that thread
/// owns none.
pub extern "C" fn proton_runtime_signal_wakeup_ffi() -> Unit = "proton_runtime_signal_wakeup"

///|
pub extern "C" fn proton_host_loop_begin_ffi() -> Int = "proton_host_loop_begin"

///|
/// `timeout_ms` follows the same encoding as `proton_runtime_wait_ffi`.
#borrow(out_ready_mask)
pub extern "C" fn proton_host_loop_poll_ffi(
  timeout_ms : Int,
  out_ready_mask : Ref[Int],
) -> Int = "proton_host_loop_poll"

///|
pub extern "C" fn proton_host_loop_end_ffi() -> Unit = "proton_host_loop_end"

///|
pub extern "C" fn proton_runtime_set_wakeup_fd_ffi(
  runtime : RuntimeHandle,
  wakeup_fd : Int,
) -> Int = "proton_runtime_set_wakeup_fd"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_runtime_prepare_wakeup_source_ffi(
  runtime : RuntimeHandle,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_runtime_prepare_wakeup_source"

///|
pub extern "C" fn proton_runtime_activate_wakeup_source_ffi(
  runtime : RuntimeHandle,
) -> Int = "proton_runtime_activate_wakeup_source"

///|
#borrow(out_delay_ms)
pub extern "C" fn proton_runtime_next_wakeup_delay_ms_ffi(
  runtime : RuntimeHandle,
  out_delay_ms : Ref[Int64],
) -> Int = "proton_runtime_next_wakeup_delay_ms"

///|
#borrow(menu_json)
pub extern "C" fn proton_runtime_set_menu_json_ffi(
  runtime : RuntimeHandle,
  menu_json : Bytes,
) -> Int = "proton_runtime_set_menu_json"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_runtime_poll_event_json_ffi(
  runtime : RuntimeHandle,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_runtime_poll_event_json"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_runtime_poll_bridge_request_json_ffi(
  runtime : RuntimeHandle,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_runtime_poll_bridge_request_json"

///|
#borrow(response_json)
pub extern "C" fn proton_runtime_respond_bridge_request_json_ffi(
  runtime : RuntimeHandle,
  response_json : Bytes,
) -> Int = "proton_runtime_respond_bridge_request_json"

///|
#borrow(title, message, out_dialog)
pub extern "C" fn proton_runtime_begin_message_dialog_ffi(
  runtime : RuntimeHandle,
  title : Bytes,
  title_len : Int,
  message : Bytes,
  message_len : Int,
  level : Int,
  out_dialog : Ref[Int64],
) -> Int = "proton_runtime_begin_message_dialog"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_runtime_poll_dialog_result_ffi(
  runtime : RuntimeHandle,
  dialog : Int64,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_runtime_poll_dialog_result"

///|
#borrow(out_supported)
pub extern "C" fn proton_notification_is_supported_ffi(
  out_supported : Ref[Int],
) -> Int = "proton_notification_is_supported"

///|
#borrow(title, body, payload)
pub extern "C" fn proton_notification_show_ffi(
  title : Bytes,
  body : Bytes,
  payload : Bytes,
  has_payload : Int,
) -> Int = "proton_notification_show"

///|
#borrow(buffer, out_required_len, out_has_payload, out_available)
pub extern "C" fn proton_notification_poll_click_ffi(
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
  out_has_payload : Ref[Int],
  out_available : Ref[Int],
) -> Int = "proton_notification_poll_click"

///|
pub extern "C" fn proton_notification_cleanup_ffi() -> Int = "proton_notification_cleanup"

///|
#borrow(title, initial_url, titlebar_minimize_label, titlebar_maximize_label, titlebar_restore_label, titlebar_close_label, bridge_config_json, out_window)
pub extern "C" fn window_create(
  runtime : RuntimeHandle,
  title : Bytes,
  width : Int,
  height : Int,
  initial_url : Bytes,
  size_hint : Int,
  titlebar_overlay : Int,
  navigation_policy : Int,
  titlebar_minimize_label : Bytes,
  titlebar_maximize_label : Bytes,
  titlebar_restore_label : Bytes,
  titlebar_close_label : Bytes,
  popup_policy : Int,
  download_policy : Int,
  certificate_policy : Int,
  media_policy : Int,
  devtools : Int,
  bridge_config_json : Bytes,
  out_window : Ref[WindowHandle],
) -> Int = "proton_internal_window_create"

///|
pub extern "C" fn proton_window_destroy_ffi(window : WindowHandle) -> Int = "proton_window_destroy"

///|
pub extern "C" fn proton_window_show_ffi(window : WindowHandle) -> Int = "proton_window_show"

///|
pub extern "C" fn proton_window_hide_ffi(window : WindowHandle) -> Int = "proton_window_hide"

///|
pub extern "C" fn proton_window_close_ffi(window : WindowHandle) -> Int = "proton_window_close"

///|
pub extern "C" fn proton_window_focus_ffi(window : WindowHandle) -> Int = "proton_window_focus"

///|
#borrow(title)
pub extern "C" fn proton_window_set_title_ffi(
  window : WindowHandle,
  title : Bytes,
) -> Int = "proton_window_set_title"

///|
pub extern "C" fn proton_window_set_size_ffi(
  window : WindowHandle,
  width : Int,
  height : Int,
) -> Int = "proton_window_set_size"

///|
pub extern "C" fn proton_window_minimize_ffi(window : WindowHandle) -> Int = "proton_window_minimize"

///|
pub extern "C" fn proton_window_maximize_ffi(window : WindowHandle) -> Int = "proton_window_maximize"

///|
pub extern "C" fn proton_window_restore_ffi(window : WindowHandle) -> Int = "proton_window_restore"

///|
pub extern "C" fn proton_window_set_fullscreen_ffi(
  window : WindowHandle,
  fullscreen : Int,
) -> Int = "proton_window_set_fullscreen"

///|
pub extern "C" fn proton_window_set_position_ffi(
  window : WindowHandle,
  x : Int,
  y : Int,
) -> Int = "proton_window_set_position"

///|
pub extern "C" fn proton_window_set_always_on_top_ffi(
  window : WindowHandle,
  always_on_top : Int,
) -> Int = "proton_window_set_always_on_top"

///|
pub extern "C" fn proton_window_set_zoom_percent_ffi(
  window : WindowHandle,
  zoom_percent : Int,
) -> Int = "proton_window_set_zoom_percent"

///|
#borrow(command_json)
pub extern "C" fn proton_window_browser_command_json_ffi(
  window : WindowHandle,
  command_json : Bytes,
) -> Int = "proton_window_browser_command_json"

///|
#borrow(response_json)
pub extern "C" fn proton_window_respond_browser_request_json_ffi(
  window : WindowHandle,
  response_json : Bytes,
) -> Int = "proton_window_respond_browser_request_json"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_window_state_json_ffi(
  window : WindowHandle,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_window_state_json"

///|
pub extern "C" fn proton_window_set_close_interception_ffi(
  window : WindowHandle,
  enabled : Int,
) -> Int = "proton_window_set_close_interception"

///|
pub extern "C" fn proton_window_respond_close_request_ffi(
  window : WindowHandle,
  request_id : Int64,
  allow : Int,
) -> Int = "proton_window_respond_close_request"

///|
#borrow(url)
pub extern "C" fn proton_window_load_url_ffi(
  window : WindowHandle,
  url : Bytes,
) -> Int = "proton_window_load_url"

///|
#borrow(html, base_url)
pub extern "C" fn proton_window_load_html_ffi(
  window : WindowHandle,
  html : Bytes,
  base_url : Bytes,
) -> Int = "proton_window_load_html"

///|
#borrow(html, document_url, asset_root)
pub extern "C" fn proton_window_load_asset_ffi(
  window : WindowHandle,
  html : Bytes,
  document_url : Bytes,
  asset_root : Bytes,
) -> Int = "proton_window_load_asset"

///|
#borrow(script)
pub extern "C" fn proton_window_eval_ffi(
  window : WindowHandle,
  script : Bytes,
) -> Int = "proton_window_eval"

///|
#borrow(event_json)
pub extern "C" fn proton_window_emit_bridge_event_json_ffi(
  window : WindowHandle,
  event_json : Bytes,
) -> Int = "proton_window_emit_bridge_event_json"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_window_bridge_state_json_ffi(
  window : WindowHandle,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_window_bridge_state_json"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_window_take_bridge_failure_json_ffi(
  window : WindowHandle,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_window_take_bridge_failure_json"

///|
#borrow(title, message, out_dialog)
pub extern "C" fn proton_window_begin_message_dialog_ffi(
  window : WindowHandle,
  title : Bytes,
  title_len : Int,
  message : Bytes,
  message_len : Int,
  level : Int,
  out_dialog : Ref[Int64],
) -> Int = "proton_window_begin_message_dialog"

///|
#borrow(title, message, out_dialog)
pub extern "C" fn proton_window_begin_confirm_dialog_ffi(
  window : WindowHandle,
  title : Bytes,
  title_len : Int,
  message : Bytes,
  message_len : Int,
  level : Int,
  out_dialog : Ref[Int64],
) -> Int = "proton_window_begin_confirm_dialog"

///|
#borrow(title, path, out_dialog)
pub extern "C" fn proton_window_begin_open_file_dialog_ffi(
  window : WindowHandle,
  title : Bytes,
  title_len : Int,
  path : Bytes,
  path_len : Int,
  out_dialog : Ref[Int64],
) -> Int = "proton_window_begin_open_file_dialog"

///|
#borrow(title, path, out_dialog)
pub extern "C" fn proton_window_begin_save_file_dialog_ffi(
  window : WindowHandle,
  title : Bytes,
  title_len : Int,
  path : Bytes,
  path_len : Int,
  out_dialog : Ref[Int64],
) -> Int = "proton_window_begin_save_file_dialog"

///|
#borrow(title, path, out_dialog)
pub extern "C" fn proton_window_begin_choose_directory_dialog_ffi(
  window : WindowHandle,
  title : Bytes,
  title_len : Int,
  path : Bytes,
  path_len : Int,
  out_dialog : Ref[Int64],
) -> Int = "proton_window_begin_choose_directory_dialog"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_window_poll_dialog_result_ffi(
  window : WindowHandle,
  dialog : Int64,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_window_poll_dialog_result"

///|
#borrow(buffer)
pub extern "C" fn proton_last_error_message_ffi(
  buffer : FixedArray[Byte],
  buffer_len : Int,
) -> Int = "proton_last_error_message"

///|
#borrow(initial_url, background_color, out_view)
pub extern "C" fn view_create(
  window : WindowHandle,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
  visible : Int,
  z_order : Int,
  initial_url : Bytes,
  background_color : Bytes,
  out_view : Ref[ViewHandle],
) -> Int = "proton_internal_view_create"

///|
pub extern "C" fn proton_view_destroy_ffi(view : ViewHandle) -> Int = "proton_view_destroy"

///|
pub extern "C" fn proton_view_set_bounds_ffi(
  view : ViewHandle,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Int = "proton_view_set_bounds"

///|
pub extern "C" fn proton_view_set_visible_ffi(
  view : ViewHandle,
  visible : Int,
) -> Int = "proton_view_set_visible"

///|
pub extern "C" fn proton_view_set_z_order_ffi(
  view : ViewHandle,
  z_order : Int,
) -> Int = "proton_view_set_z_order"

///|
#borrow(url)
pub extern "C" fn proton_view_load_url_ffi(
  view : ViewHandle,
  url : Bytes,
) -> Int = "proton_view_load_url"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_view_state_json_ffi(
  view : ViewHandle,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_view_state_json"

///|
#borrow(html, base_url)
pub extern "C" fn proton_view_load_html_ffi(
  view : ViewHandle,
  html : Bytes,
  base_url : Bytes,
) -> Int = "proton_view_load_html"

///|
#borrow(script)
pub extern "C" fn proton_view_eval_ffi(
  view : ViewHandle,
  script : Bytes,
) -> Int = "proton_view_eval"

///|
#borrow(command_json)
pub extern "C" fn proton_view_browser_command_json_ffi(
  view : ViewHandle,
  command_json : Bytes,
) -> Int = "proton_view_browser_command_json"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_screen_enumerate_json_ffi(
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_screen_enumerate_json"

///|
#borrow(url_utf8)
pub extern "C" fn proton_window_cookie_begin_get_json_ffi(
  window : WindowHandle,
  url_utf8 : Bytes,
  include_http_only : Int,
) -> Int = "proton_window_cookie_begin_get_json"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_window_cookie_poll_get_json_ffi(
  window : WindowHandle,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_window_cookie_poll_get_json"

///|
#borrow(cookie_json)
pub extern "C" fn proton_window_cookie_set_json_ffi(
  window : WindowHandle,
  cookie_json : Bytes,
) -> Int = "proton_window_cookie_set_json"

///|
#borrow(url_utf8, name_utf8)
pub extern "C" fn proton_window_cookie_delete_ffi(
  window : WindowHandle,
  url_utf8 : Bytes,
  name_utf8 : Bytes,
) -> Int = "proton_window_cookie_delete"

///|
pub extern "C" fn proton_window_cookie_flush_ffi(window : WindowHandle) -> Int = "proton_window_cookie_flush"

///|
pub extern "C" fn proton_window_clear_cache_ffi(window : WindowHandle) -> Int = "proton_window_clear_cache"

///|
#borrow(out_image)
pub extern "C" fn proton_image_create_empty_ffi(
  out_image : Ref[ImageHandle],
) -> Int = "proton_image_create_empty"

///|
pub extern "C" fn proton_image_destroy_ffi(image : ImageHandle) -> Int = "proton_image_destroy"

///|
#borrow(data)
pub extern "C" fn proton_image_add_png_ffi(
  image : ImageHandle,
  data : Bytes,
  data_len : Int,
  scale_factor : Double,
) -> Int = "proton_image_add_png"

///|
#borrow(data)
pub extern "C" fn proton_image_add_jpeg_ffi(
  image : ImageHandle,
  data : Bytes,
  data_len : Int,
  scale_factor : Double,
) -> Int = "proton_image_add_jpeg"

///|
#borrow(data)
pub extern "C" fn proton_image_add_bitmap_ffi(
  image : ImageHandle,
  data : Bytes,
  data_len : Int,
  width : Int,
  height : Int,
  scale_factor : Double,
) -> Int = "proton_image_add_bitmap"

///|
pub extern "C" fn proton_image_is_empty_ffi(image : ImageHandle) -> Int = "proton_image_is_empty"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_image_get_size_json_ffi(
  image : ImageHandle,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_image_get_size_json"

///|
#borrow(buffer, out_required_len, out_width, out_height)
pub extern "C" fn proton_image_to_png_ffi(
  image : ImageHandle,
  scale_factor : Double,
  with_transparency : Int,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
  out_width : Ref[Int],
  out_height : Ref[Int],
) -> Int = "proton_image_to_png"

///|
#borrow(buffer, out_required_len, out_width, out_height)
pub extern "C" fn proton_image_to_jpeg_ffi(
  image : ImageHandle,
  scale_factor : Double,
  quality : Int,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
  out_width : Ref[Int],
  out_height : Ref[Int],
) -> Int = "proton_image_to_jpeg"

///|
#borrow(buffer, out_required_len, out_width, out_height)
pub extern "C" fn proton_image_to_bitmap_ffi(
  image : ImageHandle,
  scale_factor : Double,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
  out_width : Ref[Int],
  out_height : Ref[Int],
) -> Int = "proton_image_to_bitmap"

///|
#borrow(parent_dir, out_stage, error)
pub extern "C" fn proton_update_stage_begin_ffi(
  parent_dir : Bytes,
  expected_size : Int64,
  target_revision : Int64,
  out_stage : Ref[Int64],
  error : FixedArray[Byte],
  error_len : Int,
) -> Int = "proton_update_stage_begin_revision"

///|
#borrow(chunk, error)
pub extern "C" fn proton_update_stage_write_ffi(
  stage : Int64,
  chunk : Bytes,
  chunk_len : Int,
  error : FixedArray[Byte],
  error_len : Int,
) -> Int = "proton_update_stage_write"

///|
#borrow(out_outcome, error)
pub extern "C" fn proton_update_stage_install_ffi(
  stage : Int64,
  out_outcome : Ref[Int],
  error : FixedArray[Byte],
  error_len : Int,
) -> Int = "proton_update_stage_install_outcome"

///|
#borrow(out_revision, error)
pub extern "C" fn proton_update_current_revision_ffi(
  out_revision : Ref[Int64],
  error : FixedArray[Byte],
  error_len : Int,
) -> Int = "proton_update_current_revision"

///|
#borrow(error)
pub extern "C" fn proton_update_cleanup_previous_ffi(
  error : FixedArray[Byte],
  error_len : Int,
) -> Int = "proton_update_cleanup_previous"

///|
#borrow(error)
pub extern "C" fn proton_update_stage_abort_ffi(
  stage : Int64,
  error : FixedArray[Byte],
  error_len : Int,
) -> Int = "proton_update_stage_abort"

///|
#borrow(archive, parent_dir, error)
pub extern "C" fn proton_update_install_ffi(
  archive : Bytes,
  archive_len : Int,
  parent_dir : Bytes,
  error : FixedArray[Byte],
  error_len : Int,
) -> Int = "proton_update_install"

///|
#borrow(error)
pub extern "C" fn proton_update_relaunch_ffi(
  error : FixedArray[Byte],
  error_len : Int,
) -> Int = "proton_update_relaunch"
