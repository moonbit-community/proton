///|
let file_ipc_transport_dirs : Map[String, Bool] = {}

///|
let file_ipc_target_dir = "target"

///|
let file_ipc_arg_name = "--lepus-ipc-dir"

///|
let file_ipc_env_name = "LEPUS_MBT_IPC_DIR"

///|
priv struct PendingFileIpcRequest {
  request_id : String
  complete : (IpcOpResponse) -> Unit
}

///|
priv struct StdioProcessTransportState {
  ipc_dir : String
  pending : Map[String, PendingFileIpcRequest]
  mut closed : Bool
  mut next_slot : Int
  startup_error : String?
}

///|
/// Creates the default IPC transport for local development.
///
/// The command is spawned as a child process and communicates with the webview
/// process using a MoonBit-managed local file IPC directory. The child should
/// run a `MbtProcessHost` via `run_stdio()`, which auto-detects this mode.
pub fn IpcOpTransport::stdio_process(
  command : String,
  args? : Array[String] = [],
  cwd? : String,
) -> IpcOpTransport {
  let (ipc_dir, startup_error) = match create_file_ipc_dir() {
    Ok(ipc_dir) =>
      match spawn_file_ipc_backend(command, args, cwd, ipc_dir) {
        Ok(_) => (ipc_dir, None)
        Err(message) => (ipc_dir, Some(message))
      }
    Err(message) => ("", Some(message))
  }
  let state = StdioProcessTransportState::{
    ipc_dir,
    pending: {},
    closed: startup_error is Some(_),
    next_slot: 0,
    startup_error,
  }
  IpcOpTransport::new(
    fn(request, complete) { state.enqueue(request, complete) },
    close=fn() { state.close() },
  ).with_poll(fn() { state.poll() })
}

///|
fn StdioProcessTransportState::enqueue(
  self : StdioProcessTransportState,
  request : IpcOpRequest,
  complete : (IpcOpResponse) -> Unit,
) -> Unit {
  match self.startup_error {
    Some(message) => {
      complete(IpcOpResponse::err(request.id, message))
      return
    }
    None => ()
  }
  guard !self.closed else {
    complete(
      IpcOpResponse::err(request.id, "MBT process IPC transport is closed"),
    )
    return
  }
  let slot = self.next_slot.to_string()
  self.next_slot = self.next_slot + 1
  match write_file_ipc_request(self.ipc_dir, slot, request.stringify()) {
    Ok(_) =>
      self.pending.set(slot, PendingFileIpcRequest::{
        request_id: request.id,
        complete,
      })
    Err(message) => {
      complete(IpcOpResponse::err(request.id, message))
      return
    }
  }
  if self.pending.length() > 0 {
    ignore(self.poll())
  }
}

///|
fn StdioProcessTransportState::poll(self : StdioProcessTransportState) -> Bool {
  guard !self.closed else { return false }
  let ready_slots = read_file_ipc_ready_response_slots(self.ipc_dir)
  for slot in ready_slots {
    match self.pending.get(slot) {
      Some(pending) => {
        let response = match read_file_ipc_response(self.ipc_dir, slot) {
          Ok(raw) =>
            match parse_ipc_op_response(raw) {
              Ok(response) => response
              Err(message) => IpcOpResponse::err(pending.request_id, message)
            }
          Err(message) => IpcOpResponse::err(pending.request_id, message)
        }
        self.pending.remove(slot)
        remove_file_ipc_response(self.ipc_dir, slot)
        (pending.complete)(response)
      }
      None => remove_file_ipc_response(self.ipc_dir, slot)
    }
  }
  self.pending.length() > 0
}

///|
fn StdioProcessTransportState::close(self : StdioProcessTransportState) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  write_file_ipc_shutdown(self.ipc_dir)
  for _, pending in self.pending {
    (pending.complete)(
      IpcOpResponse::err(pending.request_id, "MBT process IPC transport closed"),
    )
  }
  self.pending.clear()
}

///|
fn create_file_ipc_dir() -> Result[String, String] {
  ensure_dir(file_ipc_target_dir).bind(fn(_) {
    let mut index = file_ipc_transport_dirs.length()
    while true {
      let ipc_dir = file_ipc_target_dir + "/lepus-ipc-" + index.to_string()
      if !@mbfs.path_exists(ipc_dir) {
        return ensure_dir(ipc_dir).map(fn(_) {
          file_ipc_transport_dirs.set(ipc_dir, true)
          ipc_dir
        })
      }
      index = index + 1
    }
    Err("failed to allocate MBT process IPC directory")
  })
}

///|
fn ensure_dir(path : String) -> Result[Unit, String] {
  if @mbfs.path_exists(path) {
    Ok(())
  } else {
    try {
      @mbfs.create_dir(path)
      Ok(())
    } catch {
      err => Err(@debug.render(@debug.to_repr(err)))
    }
  }
}

///|
fn spawn_file_ipc_backend(
  command : String,
  args : Array[String],
  cwd : String?,
  ipc_dir : String,
) -> Result[Int, String] {
  let extra_env : Map[String, String] = {}
  extra_env.set(file_ipc_env_name, ipc_dir)
  let mut result : Result[Int, String] = Err("app service was not started")
  @async.run_async_main(async fn() {
    result = try {
      let pid = match cwd {
        Some(cwd) => @process.spawn_orphan(command, args, cwd~, extra_env~)
        None => @process.spawn_orphan(command, args, extra_env~)
      }
      Ok(pid)
    } catch {
      err => Err(@debug.render(@debug.to_repr(err)))
    }
  })
  result
}

///|
fn write_file_ipc_request(
  ipc_dir : String,
  slot : String,
  request_json : String,
) -> Result[Unit, String] {
  try {
    @mbfs.write_string_to_file(
      file_ipc_request_path(ipc_dir, slot),
      request_json,
    )
    @mbfs.write_string_to_file(file_ipc_request_ready_path(ipc_dir, slot), "1")
    Ok(())
  } catch {
    err => Err(@debug.render(@debug.to_repr(err)))
  }
}

///|
fn read_file_ipc_ready_response_slots(ipc_dir : String) -> Array[String] {
  let entries = @mbfs.read_dir(ipc_dir) catch { _ => [] }
  let slots : Array[String] = []
  for entry in entries {
    match file_ipc_response_slot_from_ready_file(entry) {
      Some(slot) => slots.push(slot)
      None => ()
    }
  }
  slots
}

///|
fn read_file_ipc_response(
  ipc_dir : String,
  slot : String,
) -> Result[String, String] {
  Ok(@mbfs.read_file_to_string(file_ipc_response_path(ipc_dir, slot))) catch {
    err => Err(@debug.render(@debug.to_repr(err)))
  }
}

///|
fn remove_file_ipc_response(ipc_dir : String, slot : String) -> Unit {
  @mbfs.remove_file(file_ipc_response_path(ipc_dir, slot)) catch {
    _ => ()
  }
  @mbfs.remove_file(file_ipc_response_ready_path(ipc_dir, slot)) catch {
    _ => ()
  }
}

///|
fn write_file_ipc_shutdown(ipc_dir : String) -> Unit {
  if ipc_dir != "" {
    @mbfs.write_string_to_file(file_ipc_shutdown_path(ipc_dir), "1") catch {
      _ => ()
    }
  }
}

///|
fn file_ipc_response_slot_from_ready_file(name : String) -> String? {
  let prefix_len = 4
  let suffix = ".ready"
  let suffix_len = suffix.length()
  let len = name.length()
  guard len > prefix_len + suffix_len else { return None }
  guard name[0:prefix_len].to_owned() == "res-" else { return None }
  guard name[len - suffix_len:].to_owned() == suffix else { return None }
  Some(name[prefix_len:len - suffix_len].to_owned())
}

///|
fn file_ipc_request_path(ipc_dir : String, slot : String) -> String {
  ipc_dir + "/req-" + slot + ".json"
}

///|
fn file_ipc_request_ready_path(ipc_dir : String, slot : String) -> String {
  ipc_dir + "/req-" + slot + ".ready"
}

///|
fn file_ipc_response_path(ipc_dir : String, slot : String) -> String {
  ipc_dir + "/res-" + slot + ".json"
}

///|
fn file_ipc_response_ready_path(ipc_dir : String, slot : String) -> String {
  ipc_dir + "/res-" + slot + ".ready"
}

///|
fn file_ipc_shutdown_path(ipc_dir : String) -> String {
  ipc_dir + "/shutdown"
}
