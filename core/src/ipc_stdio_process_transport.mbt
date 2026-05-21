///|
#external
priv type NativePendingIpcRequest

///|
priv type NativeIpcRequestQueue

///|
extern "C" fn native_ipc_request_queue_new(
  call_complete : FuncRef[((IpcOpResponse) -> Unit, IpcOpResponse) -> Unit],
) -> NativeIpcRequestQueue = "lepus_core_ipc_request_queue_new"

///|
#borrow(queue, id, request_json)
#owned(complete)
extern "C" fn native_ipc_request_queue_push(
  queue : NativeIpcRequestQueue,
  id : Bytes,
  request_json : Bytes,
  complete : (IpcOpResponse) -> Unit,
) -> Bool = "lepus_core_ipc_request_queue_push"

///|
#borrow(queue)
extern "C" fn native_ipc_request_queue_pop(
  queue : NativeIpcRequestQueue,
) -> NativePendingIpcRequest = "lepus_core_ipc_request_queue_pop"

///|
#borrow(queue)
extern "C" fn native_ipc_request_queue_close(
  queue : NativeIpcRequestQueue,
) -> Unit = "lepus_core_ipc_request_queue_close"

///|
extern "C" fn native_pending_ipc_request_is_stop(
  pending : NativePendingIpcRequest,
) -> Bool = "lepus_core_ipc_pending_request_is_stop"

///|
extern "C" fn native_pending_ipc_request_id(
  pending : NativePendingIpcRequest,
) -> Bytes = "lepus_core_ipc_pending_request_id"

///|
extern "C" fn native_pending_ipc_request_json(
  pending : NativePendingIpcRequest,
) -> Bytes = "lepus_core_ipc_pending_request_json"

///|
#borrow(queue, pending, response)
extern "C" fn native_pending_ipc_request_complete(
  queue : NativeIpcRequestQueue,
  pending : NativePendingIpcRequest,
  response : IpcOpResponse,
) -> Unit = "lepus_core_ipc_pending_request_complete"

///|
extern "C" fn native_pending_ipc_request_destroy(
  pending : NativePendingIpcRequest,
) -> Unit = "lepus_core_ipc_pending_request_destroy"

///|
priv struct StdioProcessTransportState {
  queue : NativeIpcRequestQueue
  executor : AsyncExecutor
  command : String
  args : Array[String]
  cwd : String?
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
  let queue = native_ipc_request_queue_new(fn(complete, response) {
    complete(response)
  })
  let state = StdioProcessTransportState::{
    queue,
    executor: AsyncExecutor::new(worker_count=1),
    command,
    args,
    cwd,
    closed: false,
  }
  let accepted = state.executor.submit(async fn() noraise {
    state.run_loop() catch {
      _ => state.fail_pending("stdio IPC transport failed")
    }
  })
  guard accepted else {
    abort("IpcOpTransport::stdio_process: failed to start transport executor")
  }
  IpcOpTransport::new(
    fn(request, complete) { state.enqueue(request, complete) },
    close=fn() { state.close() },
  )
}

///|
fn StdioProcessTransportState::enqueue(
  self : StdioProcessTransportState,
  request : IpcOpRequest,
  complete : (IpcOpResponse) -> Unit,
) -> Unit {
  guard !self.closed else {
    complete(IpcOpResponse::err(request.id, "stdio IPC transport is closed"))
    return
  }
  let pushed = native_ipc_request_queue_push(
    self.queue,
    @ffi.to_cstr(request.id),
    @ffi.to_cstr(request.stringify()),
    complete,
  )
  if !pushed {
    complete(IpcOpResponse::err(request.id, "stdio IPC transport is closed"))
  }
}

///|
async fn StdioProcessTransportState::run_loop(
  self : StdioProcessTransportState,
) -> Unit {
  let (child_stdin, parent_writer) = @process.write_to_process()
  let (parent_reader, child_stdout) = @process.read_from_process()
  @async.with_task_group(group => {
    let child = match self.cwd {
      Some(cwd) =>
        @process.spawn(
          group,
          self.command,
          self.args,
          stdin=child_stdin,
          stdout=child_stdout,
          cwd~,
          no_wait=true,
        )
      None =>
        @process.spawn(
          group,
          self.command,
          self.args,
          stdin=child_stdin,
          stdout=child_stdout,
          no_wait=true,
        )
    }
    self.process_pending(parent_writer, parent_reader)
    parent_writer.close()
    parent_reader.close()
    child.cancel()
  })
}

///|
async fn StdioProcessTransportState::process_pending(
  self : StdioProcessTransportState,
  writer : @process.WriteToProcess,
  reader : @process.ReadFromProcess,
) -> Unit {
  while true {
    let pending = native_ipc_request_queue_pop(self.queue)
    if native_pending_ipc_request_is_stop(pending) {
      native_pending_ipc_request_destroy(pending)
      break
    }
    self.process_one_pending(pending, writer, reader) catch {
      err => {
        let id = @ffi.from_cstr(native_pending_ipc_request_id(pending))
        native_pending_ipc_request_complete(
          self.queue,
          pending,
          IpcOpResponse::err(id, err.to_string()),
        )
      }
    }
    native_pending_ipc_request_destroy(pending)
  }
}

///|
async fn StdioProcessTransportState::process_one_pending(
  self : StdioProcessTransportState,
  pending : NativePendingIpcRequest,
  writer : @process.WriteToProcess,
  reader : @process.ReadFromProcess,
) -> Unit {
  let id = @ffi.from_cstr(native_pending_ipc_request_id(pending))
  let request_json = @ffi.from_cstr(native_pending_ipc_request_json(pending))
  writer.write(request_json + "\n")
  let response = match reader.read_until("\n") {
    Some(line) =>
      match parse_ipc_op_response(line.trim(chars="\r\n").to_owned()) {
        Ok(response) =>
          if response.id == id {
            response
          } else {
            IpcOpResponse::err(
              id,
              "stdio IPC response id mismatch: " + response.id,
            )
          }
        Err(message) => IpcOpResponse::err(id, message)
      }
    None => IpcOpResponse::err(id, "stdio IPC transport closed")
  }
  native_pending_ipc_request_complete(self.queue, pending, response)
}

///|
fn StdioProcessTransportState::fail_pending(
  self : StdioProcessTransportState,
  message : String,
) -> Unit {
  while true {
    let pending = native_ipc_request_queue_pop(self.queue)
    if native_pending_ipc_request_is_stop(pending) {
      native_pending_ipc_request_destroy(pending)
      break
    }
    let id = @ffi.from_cstr(native_pending_ipc_request_id(pending))
    native_pending_ipc_request_complete(
      self.queue,
      pending,
      IpcOpResponse::err(id, message),
    )
    native_pending_ipc_request_destroy(pending)
  }
}

///|
fn StdioProcessTransportState::close(self : StdioProcessTransportState) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  native_ipc_request_queue_close(self.queue)
  self.executor.close()
}
