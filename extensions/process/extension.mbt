///|
let spawn_command = @process_contract.spawn

///|
let wait_command = @process_contract.wait

///|
let kill_command = @process_contract.kill

///|
priv struct ProcessOwner {
  processes : Map[Int, @async_process.Process]
  mut next_id : Int
  mut tasks : @async.TaskGroup[Unit]?
}

///|
fn ProcessOwner::ProcessOwner() -> ProcessOwner {
  { processes: {}, next_id: 1, tasks: None, }
}

///|
async fn[X] spawn_process(
  group : @async.TaskGroup[X],
  request : @process_contract.SpawnRequest,
) -> @async_process.Process {
  @async_process.spawn(
    group,
    request.command,
    request.args,
    cwd?=request.cwd.map(cwd => cwd[:]),
    cancel_handler=@async_process.hard_cancel(),
    no_wait=true,
  )
}

///|
/// Spawns a child process and registers it in the process map.
async fn ProcessOwner::spawn(
  self : ProcessOwner,
  context : @proton.CommandContext,
  request : @process_contract.SpawnRequest,
) -> @process_contract.SpawnReply {
  guard self.tasks is Some(tasks) else {
    raise SpawnFailed(detail="process extension is not running")
  }
  let process = spawn_process(tasks, request) catch {
    error => raise SpawnFailed(detail=@debug.render(Repr(error)))
  }
  let id = self.next_id
  self.next_id = id + 1
  self.processes[id] = process
  let pid = process.pid
  context.emit(@process_contract.activity, @process_contract.ProcessActivity::{
    operation: "spawn",
    process_id: id,
  })
  @process_contract.SpawnReply::{ process_id: id, pid, }
}

///|
/// Waits for a child process to exit and returns its exit code.
async fn ProcessOwner::wait(
  self : ProcessOwner,
  context : @proton.CommandContext,
  request : @process_contract.WaitRequest,
) -> @process_contract.WaitReply {
  let process = self.lookup_process(request.process_id)
  let exit_code = process.wait() catch {
    error => raise WaitFailed(detail=@debug.render(Repr(error)))
  }
  self.processes.remove(request.process_id)
  context.emit(@process_contract.activity, @process_contract.ProcessActivity::{
    operation: "wait",
    process_id: request.process_id,
  })
  @process_contract.WaitReply::{ exit_code, }
}

///|
/// Terminates a child process.
async fn ProcessOwner::kill(
  self : ProcessOwner,
  context : @proton.CommandContext,
  request : @process_contract.KillRequest,
) -> @process_contract.KillReply {
  let process = self.lookup_process(request.process_id)
  let @async_process.CancellationHandler(kill_process) = @async_process.hard_cancel()
  kill_process(process.pid) catch {
    error => raise KillFailed(detail=@debug.render(Repr(error)))
  }
  context.emit(@process_contract.activity, @process_contract.ProcessActivity::{
    operation: "kill",
    process_id: request.process_id,
  })
  @process_contract.KillReply::{ killed: true, }
}

///|
fn ProcessOwner::lookup_process(
  self : ProcessOwner,
  process_id : Int,
) -> @async_process.Process raise ProcessExtensionError {
  match self.processes.get(process_id) {
    Some(process) => process
    None => raise UnknownProcess(process_id~)
  }
}

///|
fn ProcessOwner::close(self : ProcessOwner) -> Unit {
  self.tasks = None
  for _id, process in self.processes {
    process.cancel()
  }
  self.processes.clear()
}

///|
fn extension() -> @proton_extension.Extension {
  let owner = ProcessOwner()
  @proton_extension.typed(
    @process_contract.extension,
    fn(registrar) raise {
      registrar.bind(spawn_command, (context, request) => {
        owner.spawn(context, request)
      })
      registrar.bind(wait_command, (context, request) => {
        owner.wait(context, request)
      })
      registrar.bind(kill_command, (context, request) => {
        owner.kill(context, request)
      })
    },
    on_start=tasks => owner.tasks = Some(tasks),
    on_destroy=() => owner.close(),
  )
}

///|
/// Grants process commands to renderer targets selected by `App::capability`.
pub fn capability() -> @proton_extension.RendererCapability {
  @proton_extension.capability(extension())
}
