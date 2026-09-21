///|
async fn run_lifecycle_regressions(root : String, timeout : Int) -> Unit {
  let output_root = @fs.tmpdir(prefix="proton-e2e-lifecycle-")
  defer remove_dev_extension_tree(output_root)
  install_scenario_helper(root, output_root)
  let cases = match @env.get_env_var("PROTON_E2E_LIFECYCLE_CASE") {
    Some(name) => [name]
    None =>
      [
        "startup-quit", "startup-quit-window", "startup-quit-denied", "startup-quit-allowed",
        "initial-ready-quit", "loaded-view-close", "queued-view-close", "stale-view-close",
        "remove-view-close", "page-view-close", "parent-view-close", "cancel-during-startup",
        "initial-open", "cancel-sleep", "cancel-open", "task-success", "task-failure",
        "close-decision", "process-lifetime",
      ]
  }
  let failures : Array[String] = []
  for name in cases {
    let gate = join_path(output_root, "lifecycle-go")
    if @mbfs.path_exists(gate + ".ready") {
      @fs.remove(gate + ".ready")
    }
    if @mbfs.path_exists(gate) {
      @fs.remove(gate)
    }
    run_e2e_operation_with_timeout(timeout * 2, name, () => {
      @async.with_task_group(group => {
        let port = choose_cdp_port()
        let app = spawn_scenario_app(
          group,
          root,
          output_root,
          "lifecycle:" + name,
          port,
        )
        let mut stopped = false
        defer (if !stopped { app.process.cancel() })
        let ready = @async.with_timeout_opt(timeout, () => {
          while !@mbfs.path_exists(gate + ".ready") {
            if app_exit_code(app.process) is Some(code) {
              fail(
                "lifecycle child exited before ready: " +
                code.to_string() +
                app_output_suffix(app.output_path),
              )
            }
            @async.sleep(10)
          }
        })
        guard ready is Some(_) else {
          fail("lifecycle startup timeout" + app_output_suffix(app.output_path))
        }
        let snapshot = snapshot_scenario_process_tree(app)
        @mbfs.write_string_to_file(gate, "go")
        ignore(
          wait_for_scenario_app_shutdown(
            app,
            port.to_string(),
            snapshot,
            timeout,
          ),
        )
        assert_true(
          app_output_suffix(app.output_path).contains(
            "LIFECYCLE_PASSED " + name,
          ),
        )
        stopped = true
        println("Lifecycle regression passed: " + name)
      })
    }) catch {
      error => {
        println(
          "Lifecycle regression FAILED: " + name + " " + error.to_string(),
        )
        failures.push(name)
      }
    }
  }
  assert_eq(
    failures.length(),
    0,
    msg="failed lifecycle cases: " + failures.join(", "),
  )
}
