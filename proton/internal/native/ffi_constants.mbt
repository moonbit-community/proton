///|
let proton_process_handled = 1

///|
let proton_event_none = 2

///|
let proton_err_invalid_state = -3

///|
let proton_err_buffer_too_small = -11

///|
let proton_err_pending = -18

///|
let proton_err_stale_bridge_response = -12

///|
let proton_err_stale_window_request = -13

///|
let proton_err_stale_browser_request = -14

///|
let proton_err_update_busy = -15

///|
let proton_err_update_rollback = -16

///|
let proton_err_update_revision_mismatch = -17

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
let runtime_wait_timeout_infinite : Int = -1

///|
let proton_invalid_handle : Int64 = 0L
