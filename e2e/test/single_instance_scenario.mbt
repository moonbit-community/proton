///|
async fn spawn_single_instance_probe(
  group : @async.TaskGroup[Unit],
  root : String,
  output_root : String,
  port : Int,
  role : String,
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
  env["PROTON_INSTANCE_TEST_READY"] = join_path(output_root, "ready")
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
      let primary = spawn_single_instance_probe(
        group, root, output_root, port, "primary",
      )
      let mut stopped = false
      defer (if !stopped { primary.process.cancel() })
      while !@mbfs.path_exists(join_path(output_root, "ready")) {
        guard app_exit_code(primary.process) is None else {
          fail("primary exited before startup" + app_diagnostic_suffix(primary))
        }
        @async.sleep(50)
      }
      let snapshot = snapshot_scenario_process_tree(primary)
      let secondary = spawn_single_instance_probe(
        group, root, output_root, port, "secondary",
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
}
