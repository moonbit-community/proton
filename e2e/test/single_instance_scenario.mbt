///|
async fn spawn_single_instance_probe(
  group : @async.TaskGroup[Unit],
  root : String,
  output_root : String,
  port : Int,
  role : String,
  ready_path : String,
  release_paths? : (String, String),
  partition? : String,
) -> SpawnedScenarioApp {
  let (program, args) = scenario_app_command()
  let output_path = join_path(output_root, role + ".log")
  let output = @process.redirect_to_file(
    output_path,
    create_mode=@fs.CreateOrTruncate,
  )
  let env = app_process_env(root, output_root, "single_instance", port)
  env["PROTON_INSTANCE_TEST_IDENTIFIER"] = "dev.proton.e2e.single-instance.p" +
    port.to_string()
  env["PROTON_INSTANCE_TEST_ROLE"] = role
  env["PROTON_INSTANCE_TEST_READY"] = ready_path
  match partition {
    Some(partition) => env["PROTON_INSTANCE_TEST_PARTITION"] = partition
    None => ()
  }
  match release_paths {
    Some((released_path, stop_path)) => {
      env["PROTON_INSTANCE_TEST_RELEASED"] = released_path
      env["PROTON_INSTANCE_TEST_STOP"] = stop_path
    }
    None => ()
  }
  // Keep the single-instance persistent profile inside this test's temp tree.
  for
    key in [
      "HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME",
      "XDG_STATE_HOME",
    ] {
    env[key] = output_root
  }
  let process = @process.spawn(
    group,
    program,
    args,
    cwd=root,
    extra_env=env,
    stdout=output,
    stderr=output,
    cancel_handler=app_cancel_handler(),
    no_wait=true,
  )
  SpawnedScenarioApp::{ process, output_path, }
}

///|
async fn run_single_instance_probe(root : String, timeout : Int) -> Unit {
  let output_root = @fs.tmpdir(prefix="proton-e2e-single-instance-")
  defer remove_dev_extension_tree(output_root)
  install_scenario_helper(root, output_root)
  run_e2e_operation_with_timeout(timeout + 2000, "single instance activation", () => {
    let port = choose_cdp_port()
    @async.with_task_group(group => {
      let ready_path = join_path(output_root, "ready")
      let primary = spawn_single_instance_probe(
        group, root, output_root, port, "primary", ready_path,
      )
      let mut stopped = false
      defer (if !stopped { primary.process.cancel() })
      while !@mbfs.path_exists(ready_path) {
        guard app_exit_code(primary.process) is None else {
          fail("primary exited before startup" + app_diagnostic_suffix(primary))
        }
        @async.sleep(50)
      }
      let snapshot = snapshot_scenario_process_tree(primary)
      let secondary = spawn_single_instance_probe(
        group, root, output_root, port, "secondary", ready_path,
      )
      defer (if app_exit_code(secondary.process) is None {
        secondary.process.cancel()
      })
      wait_for_app_exit(secondary, timeout)
      assert_true(
        app_output_suffix(secondary.output_path).contains(
          "INSTANCE: secondary exited",
        ),
      )
      wait_for_app_exit(primary, timeout)
      wait_for_process_tree_stop(snapshot, timeout)
      assert_true(
        app_output_suffix(primary.output_path).contains(
          "INSTANCE: activation handled",
        ),
      )
      assert_true(
        app_output_suffix(primary.output_path).contains(
          "INSTANCE: primary exited",
        ),
      )
      stopped = true
    })
  })
  run_e2e_operation_with_timeout(timeout * 2, "single instance lock release", () => {
    run_single_instance_release_phase(root, output_root, timeout)
  })
}

///|
/// Reviews Electron's `releaseSingleInstanceLock`: once the running owner
/// releases the lock, a new launch must acquire the identity instead of
/// forwarding to the owner.
async fn run_single_instance_release_phase(
  root : String,
  output_root : String,
  timeout : Int,
) -> Unit {
  let port = choose_cdp_port()
  let ready_path = join_path(output_root, "release-ready")
  let released_path = join_path(output_root, "release-released")
  let stop_path = join_path(output_root, "release-stop")
  let successor_ready_path = join_path(output_root, "successor-ready")
  for stale in [ready_path, released_path, stop_path, successor_ready_path] {
    if @mbfs.path_exists(stale) {
      @fs.remove(stale)
    }
  }
  @async.with_task_group(group => {
    let owner = spawn_single_instance_probe(
      group,
      root,
      output_root,
      port,
      "release",
      ready_path,
      release_paths=(released_path, stop_path),
    )
    let mut owner_stopped = false
    defer (if !owner_stopped { owner.process.cancel() })
    wait_for_scenario_marker(owner, ready_path, timeout)
    wait_for_scenario_marker(owner, released_path, timeout)
    let snapshot = snapshot_scenario_process_tree(owner)
    let successor = spawn_single_instance_probe(
      group,
      root,
      output_root,
      port,
      "expect-primary",
      successor_ready_path,
      partition="successor",
    )
    defer (if app_exit_code(successor.process) is None {
      successor.process.cancel()
    })
    wait_for_scenario_marker(successor, successor_ready_path, timeout)
    wait_for_app_exit(successor, timeout)
    assert_true(
      app_output_suffix(successor.output_path).contains(
        "INSTANCE: primary lock held",
      ),
    )
    assert_true(
      app_output_suffix(successor.output_path).contains(
        "INSTANCE: expect-primary exited",
      ),
    )
    @mbfs.write_string_to_file(stop_path, "stop") catch {
      _ => fail("failed to stop the released single-instance owner")
    }
    wait_for_app_exit(owner, timeout)
    wait_for_process_tree_stop(snapshot, timeout)
    assert_true(
      app_output_suffix(owner.output_path).contains("INSTANCE: lock released"),
    )
    assert_true(
      app_output_suffix(owner.output_path).contains("INSTANCE: release exited"),
    )
    owner_stopped = true
  })
}

///|
async fn wait_for_scenario_marker(
  app : SpawnedScenarioApp,
  path : String,
  timeout : Int,
) -> Unit {
  let deadline = @async.now() + timeout.to_int64()
  while @async.now() <= deadline {
    if @mbfs.path_exists(path) {
      return
    }
    match app_exit_code(app.process) {
      Some(code) =>
        fail(
          "single-instance child exited before writing " +
          path +
          ": code=" +
          code.to_string() +
          app_diagnostic_suffix(app),
        )
      None => ()
    }
    @async.sleep(25)
  }
  fail(
    "single-instance child did not write " + path + app_diagnostic_suffix(app),
  )
}
