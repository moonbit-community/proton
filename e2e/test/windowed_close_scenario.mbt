///|
async fn spawn_windowed_close_probe(
  group : @async.TaskGroup[Unit],
  root : String,
  output_root : String,
  cdp_port : Int,
) -> SpawnedScenarioApp {
  let (program, args) = scenario_app_command()
  let output_path = join_path(output_root, "windowed-close.log")
  let output = @process.redirect_to_file(
    output_path,
    create_mode=@fs.CreateOrTruncate,
  )
  let env = app_process_env(root, output_root, "windowed_close", cdp_port)
  env["PROTON_HEADLESS"] = "0"
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
async fn run_windowed_close_probe(root : String, timeout : Int) -> Unit {
  let output_root = @fs.tmpdir(prefix="proton-e2e-windowed-close-")
  defer remove_dev_extension_tree(output_root)
  install_scenario_helper(root, output_root)
  run_e2e_operation_with_timeout(timeout + 2000, "windowed browser close", () => {
    let port = choose_cdp_port()
    @async.with_task_group(group => {
      let app = spawn_windowed_close_probe(group, root, output_root, port)
      let mut stopped = false
      defer (if !stopped { app.process.cancel() })
      wait_for_app_exit(app, timeout)
      stopped = true
    })
  })
}
