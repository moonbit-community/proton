///|
/// A native child process handle.
///
/// Created by `Process::spawn` and must be explicitly closed via
/// `Process::close` to release native resources. The handle is not
/// thread-safe and must be used from the thread that created it.
pub struct Process {
  priv handle : State
}

///|
/// Spawns a new child process.
///
/// - `command`: the program to execute (e.g. `"ls"`, `"cmd.exe"`).
/// - `args~`: command-line arguments.
/// - `cwd~`: optional working directory; `None` inherits the parent's.
/// - `capture_output~`: reserved for future use; currently ignored.
pub fn Process::spawn(
  command : String,
  args? : Array[String] = [],
  cwd? : String? = None,
  capture_output? : Bool = false,
) -> Process raise ProcessError {
  let cmd_bytes = @ffi.to_cstr(command)
  let args_bytes = encode_args(args)
  let cwd_bytes = match cwd {
    Some(dir) => @ffi.to_cstr(dir)
    None => @ffi.to_cstr("")
  }
  let capture = if capture_output { 1 } else { 0 }
  let handle = native_spawn(cmd_bytes, args_bytes, cwd_bytes, capture)
  let process = Process::{ handle, }
  let status = native_status(handle)
  if status != status_ok {
    let detail = decode_native_detail(native_last_error(handle))
    raise SpawnFailed(detail~)
  }
  process
}

///|
/// Returns the operating system process ID.
pub fn Process::pid(self : Process) -> Int {
  native_pid(self.handle)
}

///|
/// Non-blocking wait. Returns `Some(exit_code)` if the process has exited,
/// or `None` if it is still running.
pub fn Process::try_wait(self : Process) -> Int? raise ProcessError {
  let exit_code = Ref(0)
  let exited = Ref(0)
  let status = native_try_wait(self.handle, exit_code, exited)
  if status != status_ok {
    let detail = decode_native_detail(native_last_error(self.handle))
    raise WaitFailed(detail~)
  }
  if exited.val != 0 {
    Some(exit_code.val)
  } else {
    None
  }
}

///|
/// Blocking wait for the process to exit. Returns the exit code.
pub fn Process::wait(self : Process) -> Int raise ProcessError {
  let exit_code = Ref(0)
  let status = native_wait(self.handle, exit_code)
  if status != status_ok {
    let detail = decode_native_detail(native_last_error(self.handle))
    raise WaitFailed(detail~)
  }
  exit_code.val
}

///|
/// Terminates the process. On POSIX this sends SIGTERM; on Windows it calls
/// TerminateProcess. Safe to call after the process has already exited.
pub fn Process::kill(self : Process) -> Unit raise ProcessError {
  let status = native_kill(self.handle)
  if status != status_ok {
    let detail = decode_native_detail(native_last_error(self.handle))
    raise KillFailed(detail~)
  }
}

///|
/// Releases native resources associated with this process handle.
/// After calling this, the handle is no longer valid.
pub fn Process::close(self : Process) -> Unit {
  native_destroy(self.handle)
}

///|
/// Encodes an array of arguments as a null-byte-separated UTF-8 byte string.
/// Each argument is followed by a null terminator. For example,
/// `["-c", "ls -la"]` becomes `"-c\0ls -la\0"`.
fn encode_args(args : Array[String]) -> Bytes {
  if args.length() == 0 {
    return @ffi.to_cstr("")
  }
  let builder = StringBuilder::new()
  for arg in args {
    builder.write_string(arg)
    builder.write_char('\u0000')
  }
  @ffi.to_cstr(builder.to_string())
}

///|
fn decode_native_detail(bytes : Bytes) -> String {
  if bytes.is_empty() {
    return ""
  }
  @utf8.decode_lossy(bytes)
}
