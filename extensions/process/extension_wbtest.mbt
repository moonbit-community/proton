///|
async test "process backend spawns and waits for a child" {
  @async.with_task_group(group => {
    let process = spawn_process(group, @process_contract.SpawnRequest::{
      command: "moon",
      args: ["version"],
      cwd: None,
    })
    inspect(process.wait(), content="0")
  })
}
