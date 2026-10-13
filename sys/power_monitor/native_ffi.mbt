///|
pub type State

///|
extern "C" fn native_create() -> State = "moonbit_power_monitor_create"

///|
#borrow(handle, out_seconds)
extern "C" fn native_idle_seconds(
  handle : State,
  out_seconds : Ref[Int64],
) -> Int32 = "moonbit_power_monitor_idle_seconds"

///|
#borrow(handle, out_source, out_percent, out_has_percent)
extern "C" fn native_source(
  handle : State,
  out_source : Ref[Int32],
  out_percent : Ref[Int32],
  out_has_percent : Ref[Int32],
) -> Int32 = "moonbit_power_monitor_source"

///|
#borrow(handle)
extern "C" fn native_status(handle : State) -> Int32 = "moonbit_power_monitor_status"

///|
#borrow(handle)
extern "C" fn native_last_error(handle : State) -> Bytes = "moonbit_power_monitor_last_error"

///|
#borrow(handle)
extern "C" fn native_start_watching(handle : State) -> Int32 = "moonbit_power_monitor_start_watching"

///|
#borrow(handle)
extern "C" fn native_stop_watching(handle : State) -> Int32 = "moonbit_power_monitor_stop_watching"

///|
#borrow(handle, out_event)
extern "C" fn native_take_event(
  handle : State,
  out_event : Ref[Int32],
) -> Int32 = "moonbit_power_monitor_take_event"

///|
#borrow(handle)
extern "C" fn native_set_event_wakeup(
  handle : State,
  wakeup : @ffi.EventWakeup,
) -> Unit = "moonbit_power_monitor_set_event_wakeup"

///|
#borrow(handle)
extern "C" fn native_destroy(handle : State) -> Unit = "moonbit_power_monitor_destroy"

///|
let native_status_ok : Int32 = 0

///|
let native_status_backend_unavailable : Int32 = 1

///|
let native_status_operation_failed : Int32 = 2

///|
let native_source_unknown : Int32 = 0

///|
let native_source_ac : Int32 = 1

///|
let native_source_battery : Int32 = 2

///|
let native_event_suspend : Int32 = 0

///|
let native_event_resume : Int32 = 1

///|
let native_event_on_ac : Int32 = 2

///|
let native_event_on_battery : Int32 = 3

///|
let native_event_lock_screen : Int32 = 4

///|
let native_event_unlock_screen : Int32 = 5
