///|
/// Represents a native child process managed by the current platform.
pub type State

///|
/// Spawns a child process.
///
/// - `command`: UTF-8 program path.
/// - `args`: null-byte-separated UTF-8 argument list (each arg ends with \0).
/// - `cwd`: UTF-8 working directory, or empty string to inherit.
/// - `capture_output`: reserved for future use (0 = inherit stdio).
#borrow(command, args, cwd)
extern "C" fn native_spawn(
  command : Bytes,
  args : Bytes,
  cwd : Bytes,
  capture_output : Int,
) -> State = "moonbit_process_spawn"

///|
#borrow(handle)
extern "C" fn native_pid(handle : State) -> Int = "moonbit_process_pid"

///|
#borrow(handle)
extern "C" fn native_status(handle : State) -> Int = "moonbit_process_status"

///|
#borrow(handle, out_exit_code, out_exited)
extern "C" fn native_try_wait(
  handle : State,
  out_exit_code : Ref[Int],
  out_exited : Ref[Int],
) -> Int = "moonbit_process_try_wait"

///|
#borrow(handle, out_exit_code)
extern "C" fn native_wait(handle : State, out_exit_code : Ref[Int]) -> Int = "moonbit_process_wait"

///|
#borrow(handle)
extern "C" fn native_kill(handle : State) -> Int = "moonbit_process_kill"

///|
#borrow(handle)
extern "C" fn native_last_error(handle : State) -> Bytes = "moonbit_process_last_error"

///|
#borrow(handle)
extern "C" fn native_destroy(handle : State) -> Unit = "moonbit_process_destroy"

///|
let status_ok : Int = 0
