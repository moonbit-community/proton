///|
#external
priv type NativeStdioProcessTransport

///|
#borrow(command_line, cwd)
extern "C" fn native_stdio_transport_new(
  command_line : Bytes,
  cwd : Bytes,
) -> NativeStdioProcessTransport = "lepus_core_stdio_transport_new"

///|
#borrow(transport, request_json)
extern "C" fn native_stdio_transport_write(
  transport : NativeStdioProcessTransport,
  request_json : Bytes,
) -> Bool = "lepus_core_stdio_transport_write"

///|
#borrow(transport)
extern "C" fn native_stdio_transport_read_line(
  transport : NativeStdioProcessTransport,
) -> Bytes = "lepus_core_stdio_transport_read_line"

///|
#borrow(transport)
extern "C" fn native_stdio_transport_close(
  transport : NativeStdioProcessTransport,
) -> Unit = "lepus_core_stdio_transport_close"

///|
#borrow(transport)
extern "C" fn native_stdio_transport_is_open(
  transport : NativeStdioProcessTransport,
) -> Bool = "lepus_core_stdio_transport_is_open"

///|
priv struct StdioProcessTransportState {
  native : NativeStdioProcessTransport
  pending : Map[String, (IpcOpResponse) -> Unit]
  mut closed : Bool
}

///|
/// Creates the default IPC transport for local development.
///
/// The command is spawned as a child process and communicates with the webview
/// process using line-delimited JSON over stdin/stdout. The child should run a
/// `MbtProcessHost` via `run_stdio()`.
pub fn IpcOpTransport::stdio_process(
  command : String,
  args? : Array[String] = [],
  cwd? : String,
) -> IpcOpTransport {
  let state = StdioProcessTransportState::{
    native: native_stdio_transport_new(
      @ffi.to_cstr(build_stdio_command_line(command, args)),
      @ffi.to_cstr(cwd.unwrap_or("")),
    ),
    pending: {},
    closed: false,
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
  guard !self.closed && native_stdio_transport_is_open(self.native) else {
    complete(IpcOpResponse::err(request.id, "stdio IPC transport is closed"))
    return
  }
  let request_json = request.stringify()
  if native_stdio_transport_write(
      self.native,
      @ffi.to_cstr(request_json + "\n"),
    ) {
    self.pending.set(request.id, complete)
    ignore(self.poll())
  } else {
    complete(
      IpcOpResponse::err(request.id, "failed to write stdio IPC request"),
    )
  }
}

///|
fn StdioProcessTransportState::poll(self : StdioProcessTransportState) -> Bool {
  guard !self.closed else { return false }
  while true {
    let line = @ffi.from_cstr(native_stdio_transport_read_line(self.native))
    guard line != "" else { break }
    match parse_ipc_op_response(line.trim(chars="\r\n").to_owned()) {
      Ok(response) =>
        match self.pending.get(response.id) {
          Some(complete) => {
            self.pending.remove(response.id)
            complete(response)
          }
          None => ()
        }
      Err(_) => ()
    }
  }
  if !native_stdio_transport_is_open(self.native) {
    self.closed = true
    for id, complete in self.pending {
      complete(IpcOpResponse::err(id, "stdio IPC transport closed"))
    }
    self.pending.clear()
  }
  self.pending.length() > 0
}

///|
fn StdioProcessTransportState::close(self : StdioProcessTransportState) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  native_stdio_transport_close(self.native)
  for id, complete in self.pending {
    complete(IpcOpResponse::err(id, "stdio IPC transport closed"))
  }
  self.pending.clear()
}

///|
fn build_stdio_command_line(command : String, args : Array[String]) -> String {
  let builder = StringBuilder::new(size_hint=command.length() + 16)
  builder.write_string(shell_quote(command))
  for arg in args {
    builder.write_char(' ')
    builder.write_string(shell_quote(arg))
  }
  builder.to_string()
}

///|
fn shell_quote(value : String) -> String {
  let builder = StringBuilder::new(size_hint=value.length() + 2)
  builder.write_char('"')
  for _, ch in value {
    if ch == '"' || ch == '$' || ch == '`' {
      builder.write_char('\\')
    }
    builder.write_char(ch)
  }
  builder.write_char('"')
  builder.to_string()
}
