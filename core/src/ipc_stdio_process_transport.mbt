///|
priv struct PendingIpcRequest {
  request : IpcOpRequest
  complete : (IpcOpResponse) -> Unit
}

///|
priv struct StdioProcessTransportState {
  requests : @aqueue.Queue[PendingIpcRequest]
  executor : AsyncExecutor
  mut child : @process.Process?
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
    requests: @aqueue.Queue(kind=Unbounded),
    executor: AsyncExecutor::new(worker_count=1),
    child: None,
    closed: false,
  }
  let accepted = state.executor.submit(async fn() noraise {
    run_stdio_process_transport(state, command, args, cwd?) catch {
      err =>
        state.fail_transport("stdio IPC transport failed: " + err.to_string())
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
  try {
    if !self.requests.try_put(PendingIpcRequest::{ request, complete }) {
      complete(IpcOpResponse::err(request.id, "stdio IPC transport is closed"))
    }
  } catch {
    _ =>
      complete(IpcOpResponse::err(request.id, "stdio IPC transport is closed"))
  }
}

///|
fn StdioProcessTransportState::close(self : StdioProcessTransportState) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  self.requests.close(clear=false)
  match self.child {
    Some(child) => child.cancel()
    None => ()
  }
  self.executor.close()
}

///|
fn StdioProcessTransportState::fail_transport(
  self : StdioProcessTransportState,
  message : String,
) -> Unit {
  self.closed = true
  while true {
    let pending = self.requests.try_get() catch { _ => None }
    match pending {
      Some(pending) =>
        (pending.complete)(IpcOpResponse::err(pending.request.id, message))
      None => break
    }
  }
  self.requests.close(clear=true)
}

///|
async fn run_stdio_process_transport(
  state : StdioProcessTransportState,
  command : String,
  args : Array[String],
  cwd? : String,
) -> Unit {
  guard !state.closed else { return }
  let (child_stdin, parent_writer) = @process.write_to_process()
  let (parent_reader, child_stdout) = @process.read_from_process()
  @async.with_task_group(group => {
    let child = match cwd {
      Some(cwd) =>
        @process.spawn(
          group,
          command,
          args,
          stdin=child_stdin,
          stdout=child_stdout,
          cwd~,
          no_wait=true,
        )
      None =>
        @process.spawn(
          group,
          command,
          args,
          stdin=child_stdin,
          stdout=child_stdout,
          no_wait=true,
        )
    }
    state.child = Some(child)
    if state.closed {
      child.cancel()
      parent_writer.close()
    }
    let pending_by_id : Map[String, (IpcOpResponse) -> Unit] = {}
    group.spawn_bg(() => {
      write_stdio_ipc_requests(state, parent_writer, pending_by_id)
    })
    read_stdio_ipc_responses(parent_reader, pending_by_id)
    state.closed = true
    state.requests.close(clear=true)
    parent_writer.close()
    child.cancel()
  })
}

///|
async fn write_stdio_ipc_requests(
  state : StdioProcessTransportState,
  writer : @process.WriteToProcess,
  pending_by_id : Map[String, (IpcOpResponse) -> Unit],
) -> Unit {
  while true {
    let pending = Some(state.requests.get()) catch { _ => None }
    match pending {
      Some(pending) => {
        pending_by_id[pending.request.id] = pending.complete
        writer.write(pending.request.stringify() + "\n") catch {
          err => {
            pending_by_id.remove(pending.request.id)
            (pending.complete)(
              IpcOpResponse::err(
                pending.request.id,
                "failed to write IPC request: " + err.to_string(),
              ),
            )
          }
        }
      }
      None => break
    }
  }
  writer.close()
}

///|
async fn read_stdio_ipc_responses(
  reader : @process.ReadFromProcess,
  pending_by_id : Map[String, (IpcOpResponse) -> Unit],
) -> Unit {
  while reader.read_until("\n") is Some(line) {
    match parse_ipc_op_response(line.trim(chars="\r\n").to_owned()) {
      Ok(response) =>
        match pending_by_id.get(response.id) {
          Some(complete) => {
            pending_by_id.remove(response.id)
            complete(response)
          }
          None => ()
        }
      Err(_) => ()
    }
  }
  for id, complete in pending_by_id {
    complete(IpcOpResponse::err(id, "stdio IPC transport closed"))
  }
  pending_by_id.clear()
  reader.close()
}
