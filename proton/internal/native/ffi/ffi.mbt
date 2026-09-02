///|
pub fn ensure_cef_loader_linked() -> Unit {
  @mac_engine.ensure_linked()
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
#external
pub type EventHandle

///|
#external
pub type CookieSnapshotHandle

///|
#external
pub type MenuConfigHandle

///|
#external
pub type BridgeConfigHandle

///|
pub extern "C" fn runtime_null() -> RuntimeHandle = "proton_runtime_null"

///|
pub extern "C" fn window_null() -> WindowHandle = "proton_window_null"

///|
pub extern "C" fn view_null() -> ViewHandle = "proton_view_null"

///|
pub extern "C" fn image_null() -> ImageHandle = "proton_image_null"

///|
pub extern "C" fn event_null() -> EventHandle = "proton_internal_event_null"

///|
pub extern "C" fn menu_config_null() -> MenuConfigHandle = "proton_internal_menu_config_null"

///|
pub extern "C" fn bridge_config_null() -> BridgeConfigHandle = "proton_internal_bridge_config_null"

///|
pub extern "C" fn window_logical_id(window : WindowHandle) -> Int64 = "proton_window_logical_id"

///|
pub extern "C" fn view_logical_id(view : ViewHandle) -> Int64 = "proton_view_logical_id"

///|
pub extern "C" fn proton_abi_version_ffi() -> Int = "proton_abi_version"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_runtime_platform_id_ffi(
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_runtime_platform_id"

///|
#borrow(out_count)
pub extern "C" fn proton_system_preferred_language_count_ffi(
  out_count : Ref[Int],
) -> Int = "proton_system_preferred_language_count"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_system_preferred_language_at_ffi(
  index : Int,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_system_preferred_language_at"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_system_path_ffi(
  kind : Int,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_system_path"

///|
#borrow(scheme, identifier, executable, arguments, out_changed)
pub extern "C" fn proton_protocol_client_set_ffi(
  scheme : Bytes,
  identifier : Bytes,
  executable : Bytes,
  arguments : Bytes,
  arguments_len : Int,
  out_changed : Ref[Int],
) -> Int = "proton_protocol_client_set"

///|
#borrow(scheme, identifier, executable, arguments, out_removed)
pub extern "C" fn proton_protocol_client_remove_ffi(
  scheme : Bytes,
  identifier : Bytes,
  executable : Bytes,
  arguments : Bytes,
  arguments_len : Int,
  out_removed : Ref[Int],
) -> Int = "proton_protocol_client_remove"

///|
#borrow(scheme, identifier, executable, arguments, out_is_default)
pub extern "C" fn proton_protocol_client_is_default_ffi(
  scheme : Bytes,
  identifier : Bytes,
  executable : Bytes,
  arguments : Bytes,
  arguments_len : Int,
  out_is_default : Ref[Int],
) -> Int = "proton_protocol_client_is_default"

///|
#borrow(executable, arguments)
pub extern "C" fn proton_process_schedule_relaunch_ffi(
  executable : Bytes,
  arguments : Bytes,
  arguments_len : Int,
) -> Int = "proton_process_schedule_relaunch"

///|
pub extern "C" fn proton_process_run_relaunches_ffi() -> Int = "proton_process_run_relaunches"

///|
pub extern "C" fn proton_process_exit_ffi(exit_code : Int) -> Unit = "proton_process_exit"

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
pub extern "C" fn proton_runtime_begin_destroy_ffi(
  runtime : RuntimeHandle,
) -> Int = "proton_runtime_begin_destroy"

///|
#borrow(out_ready)
pub extern "C" fn proton_runtime_destroy_ready_ffi(
  runtime : RuntimeHandle,
  out_ready : Ref[Int],
) -> Int = "proton_runtime_destroy_ready"

///|
pub extern "C" fn proton_runtime_finish_destroy_ffi(
  runtime : RuntimeHandle,
) -> Int = "proton_runtime_finish_destroy"

///|
/// Safe to call from any thread and takes no handle, which is what lets a
/// foreign thread use it: handles validate thread ownership and that thread
/// owns none.
pub extern "C" fn proton_runtime_signal_wakeup_ffi() -> Unit = "proton_runtime_signal_wakeup"

///|
pub extern "C" fn proton_runtime_event_wakeup_callback_ffi() -> @proton_ffi.EventWakeup = "proton_runtime_event_wakeup_callback"

///|
pub extern "C" fn proton_host_loop_begin_ffi() -> Int = "proton_host_loop_begin"

///|
/// A negative `timeout_ms` waits until the host loop is signalled.
#borrow(out_ready_mask)
pub extern "C" fn proton_host_loop_poll_ffi(
  timeout_ms : Int,
  out_ready_mask : Ref[Int],
) -> Int = "proton_host_loop_poll"

///|
pub extern "C" fn proton_host_loop_end_ffi() -> Unit = "proton_host_loop_end"

///|
pub extern "C" fn runtime_set_menu(
  runtime : RuntimeHandle,
  menu : MenuConfigHandle,
) -> Int = "proton_internal_runtime_set_menu"

///|
pub extern "C" fn menu_popup(
  window : WindowHandle,
  x : Int,
  y : Int,
  menu : MenuConfigHandle,
) -> Int = "proton_internal_menu_popup"

///|
#borrow(out_menu)
pub extern "C" fn menu_config_create(out_menu : Ref[MenuConfigHandle]) -> Int = "proton_internal_menu_config_create"

///|
#borrow(label, out_menu_index)
pub extern "C" fn menu_config_add_menu(
  menu : MenuConfigHandle,
  label : Bytes,
  role : Int,
  out_menu_index : Ref[Int],
) -> Int = "proton_internal_menu_config_add_menu"

///|
#borrow(id, label, key, role)
pub extern "C" fn menu_config_add_item(
  menu : MenuConfigHandle,
  kind : Int,
  id : Bytes,
  label : Bytes,
  key : Bytes,
  role : Bytes,
  enabled : Int,
  visible : Int,
  checkable : Int,
  checked : Int,
) -> Int = "proton_internal_menu_config_add_item"

///|
#borrow(label)
pub extern "C" fn menu_config_begin_submenu(
  menu : MenuConfigHandle,
  label : Bytes,
) -> Int = "proton_internal_menu_config_begin_submenu"

///|
pub extern "C" fn menu_config_end_submenu(menu : MenuConfigHandle) -> Int = "proton_internal_menu_config_end_submenu"

///|
pub extern "C" fn menu_config_destroy(menu : MenuConfigHandle) -> Unit = "proton_internal_menu_config_destroy"

///|
#borrow(out_event)
pub extern "C" fn runtime_poll_event(
  runtime : RuntimeHandle,
  out_event : Ref[EventHandle],
) -> Int = "proton_internal_runtime_poll_event"

///|
#borrow(mime_type, data)
pub extern "C" fn runtime_complete_resource_request(
  runtime : RuntimeHandle,
  request_id : Int64,
  status : Int,
  mime_type : Bytes,
  data : Bytes,
  data_len : Int,
) -> Int = "proton_runtime_complete_resource_request"

///|
pub extern "C" fn event_kind(event : EventHandle) -> Int = "proton_internal_event_kind"

///|
pub extern "C" fn event_int64(event : EventHandle, field : Int) -> Int64 = "proton_internal_event_int64"

///|
pub extern "C" fn event_int(event : EventHandle, field : Int) -> Int = "proton_internal_event_int"

///|
pub extern "C" fn event_window_state_field(
  event : EventHandle,
  field : Int,
) -> Int = "proton_internal_event_window_state_field"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn event_text(
  event : EventHandle,
  field : Int,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_internal_event_text"

///|
pub extern "C" fn event_item_count(event : EventHandle) -> Int = "proton_internal_event_item_count"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn event_item(
  event : EventHandle,
  index : Int,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_internal_event_item"

///|
pub extern "C" fn event_take_cookie_snapshot(
  event : EventHandle,
) -> CookieSnapshotHandle = "proton_internal_event_take_cookie_snapshot"

///|
pub extern "C" fn cookie_snapshot_destroy(
  snapshot : CookieSnapshotHandle,
) -> Unit = "proton_internal_cookie_snapshot_destroy"

///|
#borrow(out_count)
pub extern "C" fn cookie_snapshot_count(
  snapshot : CookieSnapshotHandle,
  out_count : Ref[Int],
) -> Int = "proton_internal_cookie_snapshot_count"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn cookie_snapshot_string_field(
  snapshot : CookieSnapshotHandle,
  index : Int,
  field : Int,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_internal_cookie_snapshot_string_field"

///|
#borrow(out_value)
pub extern "C" fn cookie_snapshot_int_field(
  snapshot : CookieSnapshotHandle,
  index : Int,
  field : Int,
  out_value : Ref[Int],
) -> Int = "proton_internal_cookie_snapshot_int_field"

///|
#borrow(out_value, out_present)
pub extern "C" fn cookie_snapshot_int64_field(
  snapshot : CookieSnapshotHandle,
  index : Int,
  field : Int,
  out_value : Ref[Int64],
  out_present : Ref[Int],
) -> Int = "proton_internal_cookie_snapshot_int64_field"

///|
pub extern "C" fn event_destroy(event : EventHandle) -> Unit = "proton_internal_event_destroy"

///|
#borrow(body_json)
pub extern "C" fn proton_runtime_respond_bridge_request_ffi(
  runtime : RuntimeHandle,
  request_id : Int64,
  ok : Int,
  body_json : Bytes,
) -> Int = "proton_runtime_respond_bridge_request"

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
pub extern "C" fn proton_notification_set_badge_count_ffi(count : Int) -> Int = "proton_notification_set_badge_count"

///|
pub extern "C" fn proton_notification_cleanup_ffi() -> Int = "proton_notification_cleanup"

///|
#borrow(title, initial_url, titlebar_minimize_label, titlebar_maximize_label, titlebar_restore_label, titlebar_close_label, out_window)
pub extern "C" fn window_create(
  runtime : RuntimeHandle,
  title : Bytes,
  width : Int,
  height : Int,
  initial_url : Bytes,
  size_hint : Int,
  titlebar_overlay : Int,
  theme_preference : Int,
  navigation_policy : Int,
  titlebar_minimize_label : Bytes,
  titlebar_maximize_label : Bytes,
  titlebar_restore_label : Bytes,
  titlebar_close_label : Bytes,
  new_window_policy : Int,
  download_policy : Int,
  certificate_policy : Int,
  media_policy : Int,
  devtools : Int,
  bridge_config : BridgeConfigHandle,
  out_window : Ref[WindowHandle],
) -> Int = "proton_internal_window_create"

///|
#borrow(out_config)
pub extern "C" fn bridge_config_create(
  max_payload_bytes : Int,
  out_config : Ref[BridgeConfigHandle],
) -> Int = "proton_internal_bridge_config_create"

///|
#borrow(source_origin, out_grant_index)
pub extern "C" fn bridge_config_add_grant(
  config : BridgeConfigHandle,
  source_origin : Bytes,
  out_grant_index : Ref[Int],
) -> Int = "proton_internal_bridge_config_add_grant"

///|
#borrow(name)
pub extern "C" fn bridge_config_add_op(
  config : BridgeConfigHandle,
  grant_index : Int,
  name : Bytes,
) -> Int = "proton_internal_bridge_config_add_op"

///|
#borrow(js_namespace, out_extension_index)
pub extern "C" fn bridge_config_add_extension(
  config : BridgeConfigHandle,
  grant_index : Int,
  js_namespace : Bytes,
  out_extension_index : Ref[Int],
) -> Int = "proton_internal_bridge_config_add_extension"

///|
#borrow(api)
pub extern "C" fn bridge_config_add_extension_api(
  config : BridgeConfigHandle,
  grant_index : Int,
  extension_index : Int,
  api : Bytes,
) -> Int = "proton_internal_bridge_config_add_extension_api"

///|
#borrow(owner, name, source)
pub extern "C" fn bridge_config_add_initialization_unit(
  config : BridgeConfigHandle,
  grant_index : Int,
  owner : Bytes,
  name : Bytes,
  source : Bytes,
) -> Int = "proton_internal_bridge_config_add_initialization_unit"

///|
pub extern "C" fn bridge_config_destroy(config : BridgeConfigHandle) -> Unit = "proton_internal_bridge_config_destroy"

///|
pub extern "C" fn proton_window_destroy_ffi(window : WindowHandle) -> Int = "proton_window_destroy"

///|
pub extern "C" fn proton_window_show_ffi(window : WindowHandle) -> Int = "proton_window_show"

///|
pub extern "C" fn proton_window_show_inactive_ffi(window : WindowHandle) -> Int = "proton_window_show_inactive"

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
#borrow(path)
pub extern "C" fn proton_window_set_icon_ffi(
  window : WindowHandle,
  path : Bytes,
) -> Int = "proton_window_set_icon"

///|
pub extern "C" fn proton_window_set_parent_ffi(
  window : WindowHandle,
  parent : WindowHandle,
  modal : Int,
) -> Int = "proton_window_set_parent"

///|
pub extern "C" fn proton_window_set_size_ffi(
  window : WindowHandle,
  width : Int,
  height : Int,
) -> Int = "proton_window_set_size"

///|
pub extern "C" fn proton_window_set_content_size_ffi(
  window : WindowHandle,
  width : Int,
  height : Int,
) -> Int = "proton_window_set_content_size"

///|
#borrow(out_width, out_height)
pub extern "C" fn proton_window_get_content_size_ffi(
  window : WindowHandle,
  out_width : Ref[Int],
  out_height : Ref[Int],
) -> Int = "proton_window_get_content_size"

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
pub extern "C" fn proton_window_set_kiosk_ffi(
  window : WindowHandle,
  kiosk : Int,
) -> Int = "proton_window_set_kiosk"

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
pub extern "C" fn proton_window_set_resizable_ffi(
  window : WindowHandle,
  resizable : Int,
) -> Int = "proton_window_set_resizable"

///|
pub extern "C" fn proton_window_set_minimum_size_ffi(
  window : WindowHandle,
  width : Int,
  height : Int,
) -> Int = "proton_window_set_minimum_size"

///|
pub extern "C" fn proton_window_set_maximum_size_ffi(
  window : WindowHandle,
  width : Int,
  height : Int,
) -> Int = "proton_window_set_maximum_size"

///|
pub extern "C" fn proton_window_set_aspect_ratio_ffi(
  window : WindowHandle,
  aspect_ratio : Double,
) -> Int = "proton_window_set_aspect_ratio"

///|
pub extern "C" fn proton_window_set_movable_ffi(
  window : WindowHandle,
  movable : Int,
) -> Int = "proton_window_set_movable"

///|
pub extern "C" fn proton_window_set_opacity_ffi(
  window : WindowHandle,
  opacity : Double,
) -> Int = "proton_window_set_opacity"

///|
pub extern "C" fn proton_window_set_skip_taskbar_ffi(
  window : WindowHandle,
  skip : Int,
) -> Int = "proton_window_set_skip_taskbar"

///|
pub extern "C" fn proton_window_set_content_protection_ffi(
  window : WindowHandle,
  enabled : Int,
) -> Int = "proton_window_set_content_protection"

///|
pub extern "C" fn proton_window_set_minimizable_ffi(
  window : WindowHandle,
  minimizable : Int,
) -> Int = "proton_window_set_minimizable"

///|
pub extern "C" fn proton_window_set_maximizable_ffi(
  window : WindowHandle,
  maximizable : Int,
) -> Int = "proton_window_set_maximizable"

///|
pub extern "C" fn proton_window_set_closable_ffi(
  window : WindowHandle,
  closable : Int,
) -> Int = "proton_window_set_closable"

///|
pub extern "C" fn proton_window_set_button_visibility_ffi(
  window : WindowHandle,
  visible : Int,
) -> Int = "proton_window_set_button_visibility"

///|
pub extern "C" fn proton_window_set_focusable_ffi(
  window : WindowHandle,
  focusable : Int,
) -> Int = "proton_window_set_focusable"

///|
pub extern "C" fn proton_window_set_fullscreenable_ffi(
  window : WindowHandle,
  fullscreenable : Int,
) -> Int = "proton_window_set_fullscreenable"

///|
pub extern "C" fn proton_window_set_has_shadow_ffi(
  window : WindowHandle,
  has_shadow : Int,
) -> Int = "proton_window_set_has_shadow"

///|
pub extern "C" fn proton_window_set_ignore_mouse_events_ffi(
  window : WindowHandle,
  ignore : Int,
  forward : Int,
) -> Int = "proton_window_set_ignore_mouse_events"

///|
#borrow(color)
pub extern "C" fn proton_window_set_background_color_ffi(
  window : WindowHandle,
  color : Bytes,
) -> Int = "proton_window_set_background_color"

///|
pub extern "C" fn proton_window_set_theme_ffi(
  window : WindowHandle,
  theme_preference : Int,
) -> Int = "proton_window_set_theme"

///|
pub extern "C" fn proton_window_set_visible_on_all_workspaces_ffi(
  window : WindowHandle,
  visible : Int,
) -> Int = "proton_window_set_visible_on_all_workspaces"

///|
pub extern "C" fn proton_window_set_enabled_ffi(
  window : WindowHandle,
  enabled : Int,
) -> Int = "proton_window_set_enabled"

///|
pub extern "C" fn proton_window_set_zoom_percent_ffi(
  window : WindowHandle,
  zoom_percent : Int,
) -> Int = "proton_window_set_zoom_percent"

///|
pub extern "C" fn proton_window_set_audio_muted_ffi(
  window : WindowHandle,
  muted : Int,
) -> Int = "proton_window_set_audio_muted"

///|
#borrow(out_muted)
pub extern "C" fn proton_window_is_audio_muted_ffi(
  window : WindowHandle,
  out_muted : Ref[Int],
) -> Int = "proton_window_is_audio_muted"

///|
pub extern "C" fn proton_window_set_progress_bar_ffi(
  window : WindowHandle,
  progress : Double,
) -> Int = "proton_window_set_progress_bar"

///|
pub extern "C" fn proton_window_flash_frame_ffi(
  window : WindowHandle,
  flash : Int,
) -> Int = "proton_window_flash_frame"

///|
#borrow(command)
pub extern "C" fn proton_window_browser_command_ffi(
  window : WindowHandle,
  command : Bytes,
  download_id : Int,
) -> Int = "proton_window_browser_command"

///|
#borrow(out_focused)
pub extern "C" fn proton_window_get_browser_focus_state_ffi(
  window : WindowHandle,
  out_focused : Ref[Int],
) -> Int = "proton_window_get_browser_focus_state"

///|
#borrow(out_opened)
pub extern "C" fn proton_window_get_devtools_state_ffi(
  window : WindowHandle,
  out_opened : Ref[Int],
) -> Int = "proton_window_get_devtools_state"

///|
#borrow(url)
pub extern "C" fn proton_window_download_url_ffi(
  window : WindowHandle,
  url : Bytes,
) -> Int = "proton_window_download_url"

///|
pub extern "C" fn proton_window_print_ffi(window : WindowHandle) -> Int = "proton_window_print"

///|
#borrow(path, page_ranges, header_template, footer_template, out_request_id)
pub extern "C" fn proton_window_print_to_pdf_ffi(
  window : WindowHandle,
  path : Bytes,
  landscape : Int,
  print_background : Int,
  scale : Double,
  paper_width : Double,
  paper_height : Double,
  prefer_css_page_size : Int,
  margin_type : Int,
  margin_top : Double,
  margin_right : Double,
  margin_bottom : Double,
  margin_left : Double,
  page_ranges : Bytes,
  display_header_footer : Int,
  header_template : Bytes,
  footer_template : Bytes,
  generate_tagged_pdf : Int,
  generate_document_outline : Int,
  out_request_id : Ref[Int],
) -> Int = "proton_window_print_to_pdf"

///|
#borrow(text, out_request_id)
pub extern "C" fn proton_window_find_in_page_ffi(
  window : WindowHandle,
  text : Bytes,
  forward : Int,
  match_case : Int,
  find_next : Int,
  out_request_id : Ref[Int],
) -> Int = "proton_window_find_in_page"

///|
pub extern "C" fn proton_window_stop_find_in_page_ffi(
  window : WindowHandle,
  clear_selection : Int,
) -> Int = "proton_window_stop_find_in_page"

///|
#borrow(out_can_go_back, out_can_go_forward)
pub extern "C" fn proton_window_get_navigation_state_ffi(
  window : WindowHandle,
  out_can_go_back : Ref[Int],
  out_can_go_forward : Ref[Int],
) -> Int = "proton_window_get_navigation_state"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_window_get_browser_url_ffi(
  window : WindowHandle,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_window_get_browser_url"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_window_get_browser_title_ffi(
  window : WindowHandle,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_window_get_browser_title"

///|
#borrow(out_is_loading)
pub extern "C" fn proton_window_get_browser_loading_ffi(
  window : WindowHandle,
  out_is_loading : Ref[Int],
) -> Int = "proton_window_get_browser_loading"

///|
#borrow(action, path)
pub extern "C" fn proton_window_respond_browser_request_ffi(
  window : WindowHandle,
  request_id : Int64,
  action : Bytes,
  path : Bytes,
) -> Int = "proton_window_respond_browser_request"

///|
#borrow(out_fields)
pub extern "C" fn proton_window_get_state_ffi(
  window : WindowHandle,
  out_fields : FixedArray[Int],
  field_capacity : Int,
) -> Int = "proton_window_get_state"

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
#borrow(out_revision)
pub extern "C" fn proton_window_bridge_revision_ffi(
  window : WindowHandle,
  out_revision : Ref[Int64],
) -> Int = "proton_window_bridge_revision"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_window_bridge_state_field_ffi(
  window : WindowHandle,
  field : Int,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_window_bridge_state_field"

///|
#borrow(out_present)
pub extern "C" fn proton_window_bridge_failure_present_ffi(
  window : WindowHandle,
  out_present : Ref[Int],
) -> Int = "proton_window_bridge_failure_present"

///|
#borrow(buffer, out_required_len)
pub extern "C" fn proton_window_bridge_failure_field_ffi(
  window : WindowHandle,
  field : Int,
  buffer : FixedArray[Byte],
  buffer_len : Int,
  out_required_len : Ref[Int],
) -> Int = "proton_window_bridge_failure_field"

///|
#borrow(out_value, out_present)
pub extern "C" fn proton_window_bridge_failure_int_field_ffi(
  window : WindowHandle,
  field : Int,
  out_value : Ref[Int],
  out_present : Ref[Int],
) -> Int = "proton_window_bridge_failure_int_field"

///|
pub extern "C" fn proton_window_clear_bridge_failure_ffi(
  window : WindowHandle,
) -> Int = "proton_window_clear_bridge_failure"

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
pub extern "C" fn proton_window_cancel_dialog_ffi(
  window : WindowHandle,
  dialog : Int64,
) -> Int = "proton_window_cancel_dialog"

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
pub extern "C" fn proton_view_set_zoom_percent_ffi(
  view : ViewHandle,
  zoom_percent : Int,
) -> Int = "proton_view_set_zoom_percent"

///|
#borrow(out_zoom_percent)
pub extern "C" fn proton_view_get_zoom_percent_ffi(
  view : ViewHandle,
  out_zoom_percent : Ref[Int],
) -> Int = "proton_view_get_zoom_percent"

///|
pub extern "C" fn proton_view_set_audio_muted_ffi(
  view : ViewHandle,
  muted : Int,
) -> Int = "proton_view_set_audio_muted"

///|
#borrow(out_muted)
pub extern "C" fn proton_view_is_audio_muted_ffi(
  view : ViewHandle,
  out_muted : Ref[Int],
) -> Int = "proton_view_is_audio_muted"

///|
#borrow(url)
pub extern "C" fn proton_view_load_url_ffi(
  view : ViewHandle,
  url : Bytes,
) -> Int = "proton_view_load_url"

///|
#borrow(out_fields)
pub extern "C" fn proton_view_get_state_ffi(
  view : ViewHandle,
  out_fields : FixedArray[Int],
  field_capacity : Int,
) -> Int = "proton_view_get_state"

///|
#borrow(script)
pub extern "C" fn proton_view_eval_ffi(
  view : ViewHandle,
  script : Bytes,
) -> Int = "proton_view_eval"

///|
#borrow(command)
pub extern "C" fn proton_view_browser_command_ffi(
  view : ViewHandle,
  command : Bytes,
  download_id : Int,
) -> Int = "proton_view_browser_command"

///|
#borrow(out_focused)
pub extern "C" fn proton_view_get_browser_focus_state_ffi(
  view : ViewHandle,
  out_focused : Ref[Int],
) -> Int = "proton_view_get_browser_focus_state"

///|
#borrow(out_opened)
pub extern "C" fn proton_view_get_devtools_state_ffi(
  view : ViewHandle,
  out_opened : Ref[Int],
) -> Int = "proton_view_get_devtools_state"

///|
#borrow(text, out_request_id)
pub extern "C" fn proton_view_find_in_page_ffi(
  view : ViewHandle,
  text : Bytes,
  forward : Int,
  match_case : Int,
  find_next : Int,
  out_request_id : Ref[Int],
) -> Int = "proton_view_find_in_page"

///|
pub extern "C" fn proton_view_stop_find_in_page_ffi(
  view : ViewHandle,
  clear_selection : Int,
) -> Int = "proton_view_stop_find_in_page"

///|
#borrow(out_can_go_back, out_can_go_forward)
pub extern "C" fn proton_view_get_navigation_state_ffi(
  view : ViewHandle,
  out_can_go_back : Ref[Int],
  out_can_go_forward : Ref[Int],
) -> Int = "proton_view_get_navigation_state"

///|
#borrow(out_fields, out_screen_count)
pub extern "C" fn proton_screen_enumerate_ffi(
  out_fields : FixedArray[Int],
  field_capacity : Int,
  out_screen_count : Ref[Int],
) -> Int = "proton_screen_enumerate"

///|
#borrow(url_utf8, out_request_id)
pub extern "C" fn proton_window_cookie_begin_get_ffi(
  window : WindowHandle,
  url_utf8 : Bytes,
  include_http_only : Int,
  out_request_id : Ref[Int64],
) -> Int = "proton_window_cookie_begin_get"

///|
#borrow(url_utf8, name_utf8, value_utf8, domain_utf8, path_utf8)
pub extern "C" fn proton_window_cookie_set_ffi(
  window : WindowHandle,
  url_utf8 : Bytes,
  name_utf8 : Bytes,
  value_utf8 : Bytes,
  domain_utf8 : Bytes,
  path_utf8 : Bytes,
  secure : Int,
  http_only : Int,
  same_site : Int,
) -> Int = "proton_window_cookie_set"

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
#borrow(out_width, out_height)
pub extern "C" fn proton_image_get_size_ffi(
  image : ImageHandle,
  out_width : Ref[Int],
  out_height : Ref[Int],
) -> Int = "proton_image_get_size"

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
