///|
pub type State

///|
extern "C" fn native_create() -> State = "moonbit_screen_monitor_create"

///|
#borrow(handle)
extern "C" fn native_status(handle : State) -> Int = "moonbit_screen_monitor_status"

///|
#borrow(handle)
extern "C" fn native_last_error(handle : State) -> Bytes = "moonbit_screen_monitor_last_error"

///|
#borrow(handle)
extern "C" fn native_start_watching(handle : State) -> Int = "moonbit_screen_monitor_start_watching"

///|
#borrow(handle)
extern "C" fn native_stop_watching(handle : State) -> Int = "moonbit_screen_monitor_stop_watching"

///|
#borrow(handle)
extern "C" fn native_enumerate_json(handle : State) -> Bytes = "moonbit_screen_monitor_enumerate_json"

///|
#borrow(handle)
extern "C" fn native_cursor_point_json(handle : State) -> Bytes = "moonbit_screen_monitor_cursor_point_json"

///|
#borrow(handle)
extern "C" fn native_nearest_display_json(
  handle : State,
  x : Int,
  y : Int,
) -> Bytes = "moonbit_screen_monitor_nearest_display_json"

///|
#borrow(handle, out_event)
extern "C" fn native_take_event(handle : State, out_event : Ref[Int]) -> Int = "moonbit_screen_monitor_take_event"

///|
#borrow(handle)
extern "C" fn native_destroy(handle : State) -> Unit = "moonbit_screen_monitor_destroy"

///|
let native_status_ok : Int = 0

///|
let native_status_backend_unavailable : Int = 1

///|
let native_status_operation_failed : Int = 2

///|
let native_status_empty : Int = 3

///|
let native_event_added : Int = 0

///|
let native_event_removed : Int = 1

///|
let native_event_metrics_changed : Int = 2
