///|
fn quit_chain_log_lines(path : String) -> Array[String] {
  let content = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    _ => return []
  }
  let lines : Array[String] = []
  for raw_line in content.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.trim().to_owned()
    if line != "" {
      lines.push(line)
    }
  }
  lines
}

///|
fn quit_chain_log_text(path : String) -> String {
  let lines = quit_chain_log_lines(path)
  if lines.is_empty() {
    "(no chain steps recorded)"
  } else {
    lines.join(" -> ")
  }
}

///|
fn quit_chain_prefix_matches(
  lines : Array[String],
  expected : Array[String],
) -> Bool {
  guard lines.length() >= expected.length() else { return false }
  for index, line in expected {
    let actual = match lines.get(index) {
      Some(actual) => actual
      None => return false
    }
    if actual != line {
      return false
    }
  }
  true
}

///|
async fn wait_for_quit_chain_prefix(
  log_path : String,
  expected : Array[String],
  timeout : Int,
) -> Unit {
  let deadline = @async.now() + timeout.to_int64()
  while @async.now() <= deadline {
    if quit_chain_prefix_matches(quit_chain_log_lines(log_path), expected) {
      return
    }
    @async.sleep(25)
  }
  fail(
    "quit chain did not reach " +
    expected.join(" -> ") +
    ": log=" +
    quit_chain_log_text(log_path),
  )
}

///|
async fn wait_for_quit_chain_exact(
  log_path : String,
  expected : Array[String],
  timeout : Int,
) -> Unit {
  let deadline = @async.now() + timeout.to_int64()
  while @async.now() <= deadline {
    let lines = quit_chain_log_lines(log_path)
    if lines.length() == expected.length() &&
      quit_chain_prefix_matches(lines, expected) {
      return
    }
    @async.sleep(25)
  }
  fail(
    "quit chain log is " +
    quit_chain_log_text(log_path) +
    ", expected exactly " +
    expected.join(" -> "),
  )
}

///|
async fn wait_for_quit_chain_ready(
  app : SpawnedScenarioApp,
  ready_path : String,
  timeout : Int,
) -> Unit {
  let deadline = @async.now() + timeout.to_int64()
  while @async.now() <= deadline {
    if @mbfs.path_exists(ready_path) {
      return
    }
    match app_exit_code(app.process) {
      Some(code) =>
        fail(
          "quit chain app exited before ready: code=" +
          code.to_string() +
          app_diagnostic_suffix(app),
        )
      None => ()
    }
    @async.sleep(25)
  }
  fail("quit chain app did not become ready" + app_diagnostic_suffix(app))
}

///|
async fn wait_for_quit_chain_exit(
  app : SpawnedScenarioApp,
  log_path : String,
  expected_code : Int,
  timeout : Int,
) -> Unit {
  let deadline = @async.now() + timeout.to_int64()
  while @async.now() <= deadline {
    match app_exit_code(app.process) {
      Some(code) => {
        if code != expected_code {
          fail(
            "quit chain exited with code=" +
            code.to_string() +
            ", expected " +
            expected_code.to_string() +
            ", log=" +
            quit_chain_log_text(log_path) +
            app_diagnostic_suffix(app),
          )
        }
        return
      }
      None => ()
    }
    @async.sleep(50)
  }
  fail(
    "quit chain app did not exit within " +
    timeout.to_string() +
    "ms, log=" +
    quit_chain_log_text(log_path) +
    app_diagnostic_suffix(app),
  )
}

///|
async fn spawn_quit_chain_probe(
  group : @async.TaskGroup[Unit],
  root : String,
  output_root : String,
  mode : String,
  cdp_port : Int,
  log_path : String,
  ready_path : String,
  gate_path : String,
) -> SpawnedScenarioApp {
  let (program, args) = scenario_app_command()
  let output_path = join_path(output_root, "quit-chain-" + mode + ".log.out")
  let output = @process.redirect_to_file(
    output_path,
    create_mode=@fs.CreateOrTruncate,
  )
  let env = app_process_env(root, output_root, "quit_chain", cdp_port)
  env["PROTON_QUIT_CHAIN_MODE"] = mode
  env["PROTON_QUIT_CHAIN_LOG"] = log_path
  env["PROTON_QUIT_CHAIN_READY"] = ready_path
  env["PROTON_QUIT_CHAIN_GATE"] = gate_path
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
async fn run_quit_chain_case(
  root : String,
  output_root : String,
  mode : String,
  expected_exit : Int?,
  expected_log : Array[String],
  timeout : Int,
) -> Unit {
  let cdp_port = choose_cdp_port()
  let log_path = join_path(output_root, "quit-chain-" + mode + ".chain")
  let ready_path = join_path(output_root, "quit-chain-" + mode + ".ready")
  let gate_path = join_path(output_root, "quit-chain-" + mode + ".go")
  for stale in [log_path, ready_path, gate_path] {
    if @mbfs.path_exists(stale) {
      @fs.remove(stale)
    }
  }
  @async.with_task_group(group => {
    let app = spawn_quit_chain_probe(
      group, root, output_root, mode, cdp_port, log_path, ready_path, gate_path,
    )
    let mut stopped = false
    defer (if !stopped { app.process.cancel() })
    wait_for_quit_chain_ready(app, ready_path, timeout)
    @mbfs.write_string_to_file(gate_path, "go") catch {
      _ => fail("failed to release the quit chain gate")
    }
    match expected_exit {
      Some(code) => {
        wait_for_quit_chain_exit(app, log_path, code, timeout)
        stopped = true
        wait_for_quit_chain_exact(log_path, expected_log, 2000)
      }
      None => {
        wait_for_quit_chain_prefix(log_path, expected_log, timeout)
        // A prevented step must keep the application alive instead of
        // continuing to the next step or terminating.
        @async.sleep(400)
        match app_exit_code(app.process) {
          Some(code) =>
            fail(
              "prevented quit chain still exited with code=" +
              code.to_string() +
              app_diagnostic_suffix(app),
            )
          None => ()
        }
        wait_for_quit_chain_exact(log_path, expected_log, 1000)
      }
    }
  })
}

///|
async fn run_quit_chain_probe(root : String, timeout : Int) -> Unit {
  let output_root = @fs.tmpdir(prefix="proton-e2e-quit-chain-")
  defer remove_dev_extension_tree(output_root)
  install_scenario_helper(root, output_root)
  run_e2e_operation_with_timeout(timeout * 2, "quit event chain", () => {
    run_quit_chain_case(
      root,
      output_root,
      "quit0",
      Some(0),
      ["before-quit", "will-quit", "quit 0"],
      timeout,
    )
    run_quit_chain_case(
      root,
      output_root,
      "quit3",
      Some(3),
      ["before-quit", "will-quit", "quit 3"],
      timeout,
    )
    run_quit_chain_case(
      root,
      output_root,
      "exit7",
      Some(7),
      ["quit 7"],
      timeout,
    )
    run_quit_chain_case(
      root,
      output_root,
      "prevent-before-quit",
      None,
      ["before-quit"],
      timeout,
    )
    run_quit_chain_case(
      root,
      output_root,
      "prevent-will-quit",
      None,
      ["before-quit", "will-quit"],
      timeout,
    )
  })
}
