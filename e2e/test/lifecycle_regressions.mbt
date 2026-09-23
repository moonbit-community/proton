///|
/// Kills the renderer helpers of a running scenario app so the application
/// observes `render-process-gone`, the way Electron asks applications to review
/// a crashed or killed renderer.
async fn kill_renderer_helpers(snapshot : ProcessSnapshot) -> Unit {
  let mut killed = 0
  for pid in snapshot.pids {
    let command = match snapshot.commands.get(pid) {
      Some(command) => command
      None => continue
    }
    // Chromium names renderers with `--type=renderer` and identifies them with
    // `--renderer-client-id`; accepting either keeps the case working when a
    // platform prints only one of them.
    let names_renderer = command.contains("--type=renderer") ||
      command.contains("--renderer-client-id")
    // Linux forks renderers from a zygote helper, and the forked child keeps
    // the zygote's command line. Such a child is still a helper whose parent is
    // another helper, so kill those too instead of missing the renderer.
    let forked_from_helper = match snapshot.parents.get(pid) {
      Some(parent) => snapshot.helper_pids.contains(parent)
      None => false
    }
    guard names_renderer || forked_from_helper else { continue }
    if @path.sep == '\\' {
      ignore(
        @process.collect_output_merged(
          "taskkill",
          ["/pid", pid.to_string(), "/t", "/f"],
          no_console_window=true,
        ),
      )
    } else {
      ignore(
        @process.run(
          "/bin/kill",
          ["-9", pid.to_string()],
          inherit_env=false,
          no_console_window=true,
        ),
      )
    }
    killed = killed + 1
  }
  guard killed > 0 else {
    let observed : Array[String] = []
    for pid in snapshot.pids {
      observed.push(
        pid.to_string() +
        "(ppid=" +
        snapshot.parents.get(pid).unwrap_or(0).to_string() +
        ")=" +
        snapshot.commands.get(pid).unwrap_or("unknown"),
      )
    }
    fail(
      "process-events case found no renderer helper to terminate; helpers: " +
      observed.join(" | "),
    )
  }
}

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
        "close-decision", "process-lifetime", "app-control", "process-events",
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
        if name == "process-events" {
          // Observe renderer readiness without registering an on_view_event
          // callback, which would mask application-level dispatch regressions.
          let ready = @async.with_timeout_opt(timeout, () => {
            while !discover_targets_for_poll(cdp_target_from(port.to_string())).any(target => {
                      target.target_type == "page" &&
                      target.title == "Process Events View"
                    },
                  ) {
              @async.sleep(25)
            }
          })
          assert_true(
            ready is Some(_),
            msg="child view renderer did not become ready",
          )
        }
        let snapshot = snapshot_scenario_process_tree(app)
        @mbfs.write_string_to_file(gate, "go")
        if name == "process-events" {
          kill_renderer_helpers(snapshot)
        }
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
        if name == "process-events" {
          // The fixture runs without a single-instance route, so the session it
          // reports must be the default session on a temporary profile.
          assert_true(
            app_output_suffix(app.output_path).contains(
              "PROCESS_EVENTS session=partition=default data=temporary",
            ),
          )
        }
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
