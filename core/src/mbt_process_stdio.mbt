///|
/// Runs this MBT process host over line-delimited JSON on stdin/stdout.
///
/// A backend executable can use this from an `async fn main` to receive
/// `IpcOpRequest` frames and write `IpcOpResponse` frames:
///
/// ```mbt nocheck
/// async fn main {
///   let host = @core.MbtProcessHost::new()
///   host.op("app:ping", fn(_payload : PingPayload) { PingReply::{ ok: true } })
///   host.run_stdio()
/// }
/// ```
pub async fn MbtProcessHost::run_stdio(self : MbtProcessHost) -> Unit {
  match file_ipc_dir_from_env_or_args() {
    Some(ipc_dir) => self.run_file_ipc(ipc_dir)
    None => self.run_io(@stdio.stdin, @stdio.stdout)
  }
}

///|
/// Runs this host over any async reader/writer pair.
///
/// This is primarily useful for tests and for transports that expose pipes
/// without going through process stdio.
pub async fn[R : @io.Reader, W : @io.Writer] MbtProcessHost::run_io(
  self : MbtProcessHost,
  input : R,
  output : W,
) -> Unit {
  while input.read_until("\n") is Some(line) {
    let response = self.dispatch_json_async(line.trim(chars="\r\n").to_owned())
    output.write(response.stringify() + "\n")
  }
}

///|
async fn MbtProcessHost::run_file_ipc(
  self : MbtProcessHost,
  ipc_dir : String,
) -> Unit {
  while !self.closed && !file_ipc_shutdown_requested(ipc_dir) {
    self.process_file_ipc_requests(ipc_dir)
    @async.sleep(10)
  }
}

///|
async fn MbtProcessHost::process_file_ipc_requests(
  self : MbtProcessHost,
  ipc_dir : String,
) -> Unit {
  let entries = @mbfs.read_dir(ipc_dir) catch { _ => [] }
  for entry in entries {
    match file_ipc_request_slot_from_ready_file(entry) {
      Some(slot) => {
        let raw_request = read_file_ipc_request(ipc_dir, slot)
        remove_file_ipc_request(ipc_dir, slot)
        let response = match raw_request {
          Ok(raw) => self.dispatch_json_async(raw)
          Err(message) => IpcOpResponse::err("invalid", message)
        }
        write_file_ipc_response(ipc_dir, slot, response.stringify())
      }
      None => ()
    }
  }
}

///|
fn file_ipc_dir_from_env_or_args() -> String? {
  match @sys.get_env_var(file_ipc_env_name) {
    Some(ipc_dir) if ipc_dir != "" => Some(ipc_dir)
    _ => file_ipc_dir_from_args(@sys.get_cli_args())
  }
}

///|
fn file_ipc_dir_from_args(args : Array[String]) -> String? {
  let mut index = 0
  while index + 1 < args.length() {
    if args[index] == file_ipc_arg_name {
      return Some(args[index + 1])
    }
    index = index + 1
  }
  None
}

///|
fn file_ipc_shutdown_requested(ipc_dir : String) -> Bool {
  @mbfs.path_exists(file_ipc_shutdown_path(ipc_dir))
}

///|
fn file_ipc_request_slot_from_ready_file(name : String) -> String? {
  let prefix_len = 4
  let suffix = ".ready"
  let suffix_len = suffix.length()
  let len = name.length()
  guard len > prefix_len + suffix_len else { return None }
  guard name[0:prefix_len].to_owned() == "req-" else { return None }
  guard name[len - suffix_len:].to_owned() == suffix else { return None }
  Some(name[prefix_len:len - suffix_len].to_owned())
}

///|
fn read_file_ipc_request(
  ipc_dir : String,
  slot : String,
) -> Result[String, String] {
  Ok(@mbfs.read_file_to_string(file_ipc_request_path(ipc_dir, slot))) catch {
    err => Err(@debug.render(@debug.to_repr(err)))
  }
}

///|
fn remove_file_ipc_request(ipc_dir : String, slot : String) -> Unit {
  @mbfs.remove_file(file_ipc_request_path(ipc_dir, slot)) catch {
    _ => ()
  }
  @mbfs.remove_file(file_ipc_request_ready_path(ipc_dir, slot)) catch {
    _ => ()
  }
}

///|
fn write_file_ipc_response(
  ipc_dir : String,
  slot : String,
  response_json : String,
) -> Unit {
  @mbfs.write_string_to_file(
    file_ipc_response_path(ipc_dir, slot),
    response_json,
  ) catch {
    _ => ()
  }
  @mbfs.write_string_to_file(file_ipc_response_ready_path(ipc_dir, slot), "1") catch {
    _ => ()
  }
}
