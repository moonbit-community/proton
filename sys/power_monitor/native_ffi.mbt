///|
pub type State

///|
extern "C" fn native_create() -> State = "moonbit_power_monitor_create"

///|
#borrow(handle, out_seconds)
extern "C" fn native_idle_seconds(
  handle : State,
  out_seconds : Ref[Int64],
) -> Int = "moonbit_power_monitor_idle_seconds"

///|
#borrow(handle, out_source, out_percent, out_has_percent)
extern "C" fn native_source(
  handle : State,
  out_source : Ref[Int],
  out_percent : Ref[Int],
  out_has_percent : Ref[Int],
) -> Int = "moonbit_power_monitor_source"

///|
#borrow(handle)
extern "C" fn native_status(handle : State) -> Int = "moonbit_power_monitor_status"

///|
#borrow(handle)
extern "C" fn native_last_error(handle : State) -> Bytes = "moonbit_power_monitor_last_error"

///|
#borrow(handle)
extern "C" fn native_destroy(handle : State) -> Unit = "moonbit_power_monitor_destroy"

///|
let native_status_ok : Int = 0

///|
let native_status_backend_unavailable : Int = 1

///|
let native_status_operation_failed : Int = 2

///|
let native_source_unknown : Int = 0

///|
let native_source_ac : Int = 1

///|
let native_source_battery : Int = 2
