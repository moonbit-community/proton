///|
/// Returns the numeric platform tag reported by the native tray backend.
extern "C" fn current_platform_ffi() -> Int = "moonbit_tray_current_platform"

///|
/// Reports whether the native tray backend is available on the current machine.
extern "C" fn is_supported_ffi() -> Bool = "moonbit_tray_is_supported"

///|
/// Returns the last support-probe error message as UTF-8 bytes.
extern "C" fn support_error_ffi() -> Bytes = "moonbit_tray_support_error"

///|
/// Creates a native tray state and returns its opaque handle.
#borrow(identifier, icon, tooltip)
extern "C" fn create_state_ffi(
  identifier : Bytes,
  icon : Bytes,
  tooltip : Bytes,
) -> Int64 = "moonbit_tray_create"

///|
/// Returns the most recent create failure message as UTF-8 bytes.
extern "C" fn last_create_error_ffi() -> Bytes = "moonbit_tray_last_create_error"

///|
/// Destroys the native tray state associated with the given handle.
extern "C" fn destroy_state_ffi(state : Int64) -> Unit = "moonbit_tray_destroy"

///|
/// Shows the native tray icon and optionally updates its tooltip.
#borrow(tooltip)
extern "C" fn show_state_ffi(state : Int64, tooltip : Bytes) -> Bool = "moonbit_tray_show"

///|
/// Hides the native tray icon without freeing its handle.
extern "C" fn hide_state_ffi(state : Int64) -> Bool = "moonbit_tray_hide"

///|
/// Updates the tooltip text stored by the native tray state.
#borrow(tooltip)
extern "C" fn set_tooltip_ffi(state : Int64, tooltip : Bytes) -> Bool = "moonbit_tray_set_tooltip"

///|
/// Updates the icon path stored by the native tray state.
#borrow(icon)
extern "C" fn set_icon_ffi(state : Int64, icon : Bytes) -> Bool = "moonbit_tray_set_icon"

///|
/// Starts a native menu replacement transaction.
extern "C" fn menu_begin_ffi(state : Int64) -> Bool = "moonbit_tray_menu_begin"

///|
/// Adds a normal clickable item to the active native menu transaction.
#borrow(id, label)
extern "C" fn menu_add_normal_ffi(
  state : Int64,
  id : Bytes,
  label : Bytes,
  enabled : Int,
) -> Bool = "moonbit_tray_menu_add_normal"

///|
/// Adds a checkbox item to the active native menu transaction.
#borrow(id, label)
extern "C" fn menu_add_checkbox_ffi(
  state : Int64,
  id : Bytes,
  label : Bytes,
  enabled : Int,
  checked : Int,
) -> Bool = "moonbit_tray_menu_add_checkbox"

///|
/// Adds a separator to the active native menu transaction.
extern "C" fn menu_add_separator_ffi(state : Int64) -> Bool = "moonbit_tray_menu_add_separator"

///|
/// Starts a submenu in the active native menu transaction.
#borrow(label)
extern "C" fn menu_begin_submenu_ffi(
  state : Int64,
  label : Bytes,
  enabled : Int,
) -> Bool = "moonbit_tray_menu_begin_submenu"

///|
/// Ends the current submenu in the active native menu transaction.
extern "C" fn menu_end_submenu_ffi(state : Int64) -> Bool = "moonbit_tray_menu_end_submenu"

///|
/// Commits the active native menu transaction.
extern "C" fn menu_commit_ffi(state : Int64) -> Bool = "moonbit_tray_menu_commit"

///|
/// Aborts the active native menu transaction.
extern "C" fn menu_abort_ffi(state : Int64) -> Unit = "moonbit_tray_menu_abort"

///|
/// Pumps one native event-loop step for the given tray handle.
extern "C" fn pump_state_ffi(state : Int64, blocking : Int) -> Int = "moonbit_tray_pump"

///|
/// Polls one native tray event as a JSON payload.
extern "C" fn poll_event_json_ffi(state : Int64) -> Bytes = "moonbit_tray_poll_event_json"

///|
/// Returns the most recent state-operation error message as UTF-8 bytes.
extern "C" fn last_state_error_ffi(state : Int64) -> Bytes = "moonbit_tray_last_error"
