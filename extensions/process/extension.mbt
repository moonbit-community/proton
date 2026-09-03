///|
let spawn_command = @process_contract.spawn

///|
let wait_command = @process_contract.wait

///|
let kill_command = @process_contract.kill

///|
/// Active child processes keyed by an incrementing integer id.
let processes : Ref[Map[Int, @async_process.Process]] = Ref(Map([]))

///|
let next_process_id : Ref[Int] = Ref(1)

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
#proton.command(contract=spawn_command)
async fn spawn(
  context : @proton.CommandContext,
  request : @process_contract.SpawnRequest,
) -> @process_contract.SpawnReply {
  let process = spawn_process(context.task_group(), request) catch {
    error => raise SpawnFailed(detail=@debug.render(Repr(error)))
  }
  let id = next_process_id.val
  next_process_id.val = id + 1
  processes.val[id] = process
  let pid = process.pid
  context.emit(@process_contract.activity, @process_contract.ProcessActivity::{
    operation: "spawn",
    process_id: id,
  })
  @process_contract.SpawnReply::{ process_id: id, pid, }
}

///|
/// Waits for a child process to exit and returns its exit code.
#proton.command(contract=wait_command)
async fn wait(
  context : @proton.CommandContext,
  request : @process_contract.WaitRequest,
) -> @process_contract.WaitReply {
  let process = lookup_process(request.process_id)
  let exit_code = process.wait() catch {
    error => raise WaitFailed(detail=@debug.render(Repr(error)))
  }
  processes.val.remove(request.process_id)
  context.emit(@process_contract.activity, @process_contract.ProcessActivity::{
    operation: "wait",
    process_id: request.process_id,
  })
  @process_contract.WaitReply::{ exit_code, }
}

///|
/// Terminates a child process.
#proton.command(contract=kill_command)
async fn kill(
  context : @proton.CommandContext,
  request : @process_contract.KillRequest,
) -> @process_contract.KillReply {
  let process = lookup_process(request.process_id)
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
fn lookup_process(
  process_id : Int,
) -> @async_process.Process raise ProcessExtensionError {
  match processes.val.get(process_id) {
    Some(process) => process
    None => raise UnknownProcess(process_id~)
  }
}

///|
fn cleanup_processes() -> Unit {
  for _id, process in processes.val {
    process.cancel()
  }
  processes.val.clear()
}

///|
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @process_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
    on_destroy=fn() { cleanup_processes() },
  )
}

///|
/// Grants process commands to renderer targets selected by `App::capability`.
pub fn capability() -> @proton_extension.RendererCapability {
  @proton_extension.capability(extension())
}
