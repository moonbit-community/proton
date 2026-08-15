///|
let spawn_command = @process_contract.spawn

///|
let wait_command = @process_contract.wait

///|
let kill_command = @process_contract.kill

///|
/// Active child processes keyed by an incrementing integer id.
let processes : Ref[Map[Int, @sys_process.Process]] = Ref(Map([]))

///|
let next_process_id : Ref[Int] = Ref(1)

///|
/// Spawns a child process and registers it in the process map.
#proton.command(contract=spawn_command)
async fn spawn(
  context : @proton.CommandContext,
  request : @process_contract.SpawnRequest,
) -> @process_contract.SpawnReply {
  let process = @sys_process.Process::spawn(
    request.command,
    args=request.args,
    cwd=request.cwd,
  ) catch {
    error => raise SpawnFailed(detail=error.to_string())
  }
  let id = next_process_id.val
  next_process_id.val = id + 1
  processes.val[id] = process
  let pid = process.pid()
  context.emit(@process_contract.activity, @process_contract.ProcessActivity::{
    operation: "spawn",
    process_id: id,
  })
  @process_contract.SpawnReply::{ process_id: id, pid }
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
    error => raise WaitFailed(detail=error.to_string())
  }
  processes.val.remove(request.process_id)
  process.close()
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
  process.kill() catch {
    error => raise KillFailed(detail=error.to_string())
  }
  context.emit(@process_contract.activity, @process_contract.ProcessActivity::{
    operation: "kill",
    process_id: request.process_id,
  })
  @process_contract.KillReply::{ killed: true }
}

///|
fn lookup_process(
  process_id : Int,
) -> @sys_process.Process raise ProcessExtensionError {
  match processes.val.get(process_id) {
    Some(process) => process
    None => raise UnknownProcess(process_id~)
  }
}

///|
fn cleanup_processes() -> Unit {
  for _id, process in processes.val {
    process.close()
  }
  processes.val.clear()
}

///|
pub fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    @process_contract.extension,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
    on_destroy=fn() { cleanup_processes() },
  )
}
