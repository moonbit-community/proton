///|
async fn process_request(
  host : @core.AppCommandHost,
  name : String,
  body : Json,
) -> @ipc.IpcOpResponse {
  let response : Ref[@ipc.IpcOpResponse?] = Ref(None)
  @async.with_task_group(request_tasks => {
    response.val = Some(
      host.dispatch_ipc_with_context(
        @core.AppCommandRequestContext::detached(request_tasks),
        @ipc.IpcOpRequest("test", "ext:process/" + name, body),
      ),
    )
    request_tasks.return_immediately(())
  })
  response.val.unwrap()
}

///|
async test "spawned child survives the spawning request" {
  let spec = extension().command_spec()
  let host = @core.AppCommandHost()
  spec.register(@proton.CommandRegistrar(host))
  host.seal_registrations()
  defer (spec.destroy() catch { _ => () })
  @async.with_task_group(owner_tasks => {
    spec.start(owner_tasks)
    let spawned = process_request(host, "spawn", {
      "command": "node",
      "args": ["-e", "setTimeout(() => process.exit(7), 500)"],
    })
    assert_true(spawned.is_ok(), msg=spawned.body.stringify())
    let reply : @process_contract.SpawnReply = @json.from_json(spawned.body)
    let waited = process_request(host, "wait", {
      "process_id": reply.process_id,
    })
    assert_true(waited.is_ok(), msg=waited.body.stringify())
    let result : @process_contract.WaitReply = @json.from_json(waited.body)
    assert_eq(result.exit_code, 7)
  })
}

///|
async test "kill and wait use separate requests and extension registries are isolated" {
  let spec = extension().command_spec()
  let other = extension().command_spec()
  let host = @core.AppCommandHost()
  let other_host = @core.AppCommandHost()
  spec.register(@proton.CommandRegistrar(host))
  other.register(@proton.CommandRegistrar(other_host))
  host.seal_registrations()
  other_host.seal_registrations()
  defer (spec.destroy() catch { _ => () })
  defer (other.destroy() catch { _ => () })
  @async.with_task_group(owner_tasks => {
    spec.start(owner_tasks)
    other.start(owner_tasks)
    let spawned = process_request(host, "spawn", {
      "command": "node",
      "args": ["-e", "setInterval(() => {}, 1000)"],
    })
    assert_true(spawned.is_ok())
    let reply : @process_contract.SpawnReply = @json.from_json(spawned.body)
    assert_false(
      process_request(other_host, "kill", { "process_id": reply.process_id }).is_ok(),
    )
    assert_true(
      process_request(host, "kill", { "process_id": reply.process_id }).is_ok(),
    )
    assert_true(
      process_request(host, "wait", { "process_id": reply.process_id }).is_ok(),
    )
    assert_false(
      process_request(host, "wait", { "process_id": reply.process_id }).is_ok(),
    )
  })
}

///|
async test "owner shutdown reaps children and clears the registry" {
  let owner = ProcessOwner()
  let child : Ref[@async_process.Process?] = Ref(None)
  @async.with_task_group(owner_tasks => {
    owner.tasks = Some(owner_tasks)
    @async.with_task_group(request_tasks => {
      let reply = owner.spawn(@proton.CommandContext::detached(request_tasks), {
        command: "node",
        args: ["-e", "setInterval(() => {}, 1000)"],
        cwd: None,
      })
      child.val = Some(owner.lookup_process(reply.process_id))
      request_tasks.return_immediately(())
    })
    assert_true(child.val.unwrap().try_wait() is None)
    owner_tasks.return_immediately(())
  })
  // Exiting the owning task group joins the process cancellation task.
  try ignore(child.val.unwrap().try_wait()) catch {
    error => assert_true(@async.is_cancellation_error(error))
  } noraise {
    _ => fail("expected child cancellation at owner shutdown")
  }
  @async.with_task_group(probe_tasks => {
    let probe = spawn_process(probe_tasks, {
      command: "node",
      args: [
        "-e",
        "try { process.kill(" +
        child.val.unwrap().pid.to_string() +
        ", 0); process.exit(1); } catch (e) { process.exit(e.code === 'ESRCH' ? 0 : 2); }",
      ],
      cwd: None,
    })
    assert_eq(probe.wait(), 0)
  })
  owner.close()
  assert_eq(owner.processes.length(), 0)
  assert_true(owner.tasks is None)
  owner.close()
}
