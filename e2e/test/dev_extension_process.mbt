///|
struct DevExtensionFrontendState {
  node_modules_dir : String
  had_node_modules : Bool
  dist_dir : String
  had_dist : Bool
}

///|
fn dev_extension_frontend_state(root : String) -> DevExtensionFrontendState {
  let frontend_dir = join_path(root, "examples/47_dev_extension_js/frontend")
  let node_modules_dir = join_path(frontend_dir, "node_modules")
  let dist_dir = join_path(frontend_dir, "dist")
  let had_node_modules = @mbfs.path_exists(node_modules_dir)
  let had_dist = @mbfs.path_exists(dist_dir)
  DevExtensionFrontendState::{
    node_modules_dir,
    had_node_modules,
    dist_dir,
    had_dist,
  }
}

///|
async fn ensure_dev_extension_frontend(
  root : String,
  output_root : String,
  timeout : Int,
) -> Unit {
  let frontend_dir = join_path(root, "examples/47_dev_extension_js/frontend")
  let vite = dev_extension_vite_binary(frontend_dir)
  if !@mbfs.path_exists(vite) {
    let (program, args) = dev_extension_npm_command([
      "ci", "--no-audit", "--no-fund",
    ])
    run_dev_extension_command(
      output_root,
      "47-npm-ci",
      program,
      args,
      frontend_dir,
      Map([]),
      dev_extension_command_timeout(timeout),
    )
  }
  guard @mbfs.path_exists(vite) else {
    fail("Vite executable was not installed: " + vite)
  }
}

///|
fn dev_extension_vite_binary(frontend_dir : String) -> String {
  let executable = if @path.sep == '\\' { "vite.cmd" } else { "vite" }
  join_path(frontend_dir, "node_modules/.bin/" + executable)
}

///|
fn dev_extension_npm_command(args : Array[String]) -> (String, Array[String]) {
  if @path.sep == '\\' {
    let command_args = ["/c", "npm.cmd"]
    for arg in args {
      command_args.push(arg)
    }
    ("cmd", command_args)
  } else {
    ("npm", args)
  }
}

///|
fn dev_extension_command_timeout(timeout : Int) -> Int {
  if @path.sep == '\\' && timeout < 180000 {
    180000
  } else {
    timeout
  }
}

///|
fn dev_extension_build_timeout(timeout : Int, has_linux_cef : Bool) -> Int {
  let timeout = dev_extension_command_timeout(timeout)
  if has_linux_cef && timeout < 180000 {
    180000
  } else {
    timeout
  }
}

///|
fn process_snapshot_suffix(snapshot : ProcessSnapshot) -> String {
  let details : Array[String] = []
  for pid in snapshot.pids {
    details.push(
      pid.to_string() + ":" + snapshot.commands.get(pid).unwrap_or("unknown"),
    )
  }
  if details.length() == 0 {
    ""
  } else {
    "\nProcess tree:\n" + details.join("\n")
  }
}

///|
fn dev_extension_cli_target_dir(
  output_root : String,
  phase : String,
  port : Int,
) -> String {
  join_path(output_root, "cli-" + phase + "-" + port.to_string())
}

///|
fn dev_extension_app_target_dir(
  output_root : String,
  phase : String,
  port : Int,
) -> String {
  join_path(output_root, "app-" + phase + "-" + port.to_string())
}

///|
fn dev_extension_example_target_dir(output_root : String, port : Int) -> String {
  join_path(output_root, "example-" + port.to_string())
}

///|
async fn run_dev_extension_command(
  output_root : String,
  name : String,
  program : String,
  args : Array[String],
  cwd : String,
  env : Map[String, String],
  timeout : Int,
) -> Unit {
  let output_path = join_path(output_root, name + ".log")
  @async.with_task_group(group => {
    let output = @process.redirect_to_file(
      output_path,
      create_mode=@fs.CreateOrTruncate,
    )
    let (program, args) = isolated_app_command(program, args)
    let process = @process.spawn(
      group,
      program,
      args,
      cwd~,
      extra_env=env,
      stdout=output,
      stderr=output,
      cancel_handler=app_cancel_handler(),
      no_wait=true,
    )
    let mut finished = false
    defer (if !finished { process.cancel() })
    let mut elapsed = 0
    while elapsed <= timeout {
      match app_exit_code(process) {
        Some(code) => {
          finished = true
          guard code == 0 else {
            fail(
              name +
              " failed with code=" +
              code.to_string() +
              app_output_suffix(output_path),
            )
          }
          return
        }
        None => {
          @async.sleep(100)
          elapsed = elapsed + 100
        }
      }
    }
    let snapshot = snapshot_process_tree(process.pid)
    fail(
      name +
      " did not finish within " +
      timeout.to_string() +
      "ms" +
      app_output_suffix(output_path) +
      process_snapshot_suffix(snapshot),
    )
  })
}

///|
async fn dev_extension_runtime_env(
  root : String,
  output_root : String,
  cdp_port : Int,
) -> Map[String, String] {
  let env = app_process_env(root, output_root, "47_dev_extension_js", cdp_port)
  env["NO_COLOR"] = "1"
  env["FORCE_COLOR"] = "0"
  env["PROTON_NO_UPDATE_CHECK"] = "1"
  env["PROTON_RESOURCE_DIR"] = join_path(root, "examples/47_dev_extension_js")
  env
}

///|
fn restore_dev_extension_parent_preload(
  env : Map[String, String],
  parent_preload : String?,
) -> Unit {
  match parent_preload {
    Some(value) => env["LD_PRELOAD"] = value
    None => env.remove("LD_PRELOAD")
  }
}

///|
async fn dev_extension_host_env(
  root : String,
  output_root : String,
  cdp_port : Int,
) -> Map[String, String] {
  let env = dev_extension_runtime_env(root, output_root, cdp_port)
  // app_process_env injects libcef.so for Linux application children. The
  // CLI/build hosts launch Moon or Node rather than CEF, so restore the
  // caller's preload instead of leaking the injected CEF wrapper into them.
  restore_dev_extension_parent_preload(env, @env.get_env_var("LD_PRELOAD"))
  env
}

///|
async fn spawn_dev_extension_cli_app(
  group : @async.TaskGroup[Unit],
  root : String,
  output_root : String,
  cdp_port : Int,
  frontend_port : Int,
) -> SpawnedScenarioApp {
  let output_path = join_path(
    output_root,
    "child-" + cdp_port.to_string() + ".log",
  )
  let output = @process.redirect_to_file(
    output_path,
    create_mode=@fs.CreateOrTruncate,
  )
  let frontend_url = "http://127.0.0.1:" + frontend_port.to_string()
  let frontend_command = "npm run dev -- --host 127.0.0.1 --port " +
    frontend_port.to_string() +
    " --strictPort"
  let args = [
    "-C",
    join_path(root, "cli"),
    "--target-dir",
    dev_extension_cli_target_dir(output_root, "dev", cdp_port),
    "run",
    ".",
    "--",
    "-C",
    root,
    "dev",
    "--config",
    "examples/47_dev_extension_js/proton.project.json",
    "--moon-target-dir",
    dev_extension_app_target_dir(output_root, "dev", cdp_port),
    "--url",
    frontend_url,
    "--command",
    frontend_command,
    "--frontend-path",
    "frontend",
    "--timeout-ms",
    timeout_ms().to_string(),
  ]
  let (program, args) = isolated_app_command("moon", args)
  let process = @process.spawn(
    group,
    program,
    args,
    cwd=root,
    extra_env=dev_extension_host_env(root, output_root, cdp_port),
    stdout=output,
    stderr=output,
    cancel_handler=app_cancel_handler(),
    no_wait=true,
  )
  SpawnedScenarioApp::{
    process,
    output_path,
    native_log_path: scenario_native_log_path(output_root, cdp_port),
  }
}

///|
async fn spawn_dev_extension_production_app(
  group : @async.TaskGroup[Unit],
  root : String,
  output_root : String,
  cdp_port : Int,
) -> SpawnedScenarioApp {
  let output_path = join_path(
    output_root,
    "child-" + cdp_port.to_string() + ".log",
  )
  let output = @process.redirect_to_file(
    output_path,
    create_mode=@fs.CreateOrTruncate,
  )
  let (program, args) = isolated_app_command("moon", [
    "-C",
    join_path(root, "examples"),
    "--target-dir",
    dev_extension_example_target_dir(output_root, cdp_port),
    "run",
    "47_dev_extension_js",
    "--target",
    "native",
    "--diagnostic-limit",
    "120",
  ])
  let process = @process.spawn(
    group,
    program,
    args,
    cwd=root,
    extra_env=dev_extension_runtime_env(root, output_root, cdp_port),
    stdout=output,
    stderr=output,
    cancel_handler=app_cancel_handler(),
    no_wait=true,
  )
  SpawnedScenarioApp::{
    process,
    output_path,
    native_log_path: scenario_native_log_path(output_root, cdp_port),
  }
}

///|
async fn build_dev_extension_frontend(
  root : String,
  output_root : String,
  timeout : Int,
) -> Unit {
  let runtime_dist = active_runtime_dist()
  let has_linux_cef = @mbfs.path_exists(
    join_path(runtime_dist, "bin/libcef.so"),
  )
  let timeout = dev_extension_build_timeout(timeout, has_linux_cef)
  let port = choose_cdp_port()
  let env = dev_extension_host_env(root, output_root, port)
  let cli_target_dir = dev_extension_cli_target_dir(output_root, "build", port)
  let app_target_dir = dev_extension_app_target_dir(output_root, "build", port)
  defer {
    remove_dev_extension_tree(cli_target_dir)
    remove_dev_extension_tree(app_target_dir)
  }
  run_dev_extension_command(
    output_root,
    "47-proton-build",
    "moon",
    [
      "-C",
      join_path(root, "cli"),
      "--target-dir",
      cli_target_dir,
      "run",
      ".",
      "--",
      "-C",
      root,
      "build",
      "--config",
      "examples/47_dev_extension_js/proton.project.json",
      "--moon-target-dir",
      app_target_dir,
    ],
    root,
    env,
    timeout,
  )
}

///|
async fn run_dev_extension_dev_probe_once(
  root : String,
  output_root : String,
  frontend_port : Int,
  timeout : Int,
) -> Unit {
  let cdp_port = choose_cdp_port()
  let target = cdp_port.to_string()
  let frontend_url = "http://127.0.0.1:" + frontend_port.to_string()
  let cli_target_dir = dev_extension_cli_target_dir(
    output_root, "dev", cdp_port,
  )
  let app_target_dir = dev_extension_app_target_dir(
    output_root, "dev", cdp_port,
  )
  @async.with_task_group(group => {
    let app = spawn_dev_extension_cli_app(
      group, root, output_root, cdp_port, frontend_port,
    )
    let mut stopped = false
    defer {
      if !stopped {
        app.process.cancel()
      }
      remove_dev_extension_tree(cli_target_dir)
      remove_dev_extension_tree(app_target_dir)
    }
    ignore(
      wait_for_spawned_app_cdp(app, cdp_http_endpoint_from(target), timeout),
    )
    run_dev_extension_page_probe(
      group, app, target, frontend_url, output_root, timeout,
    )
    match app_exit_code(app.process) {
      Some(code) =>
        fail(
          "dev extension CLI exited before the probe completed: code=" +
          code.to_string() +
          app_output_suffix(app.output_path),
        )
      None => ()
    }
    let shutdown = finish_scenario_app_with_exit_timeout(app, target, 30000)
    println(
      "MoonBit 47_dev_extension_js dev shutdown passed: helpers=" +
      shutdown.helper_processes.to_string(),
    )
    stopped = true
  })
}

///|
async fn run_dev_extension_production_probe_once(
  root : String,
  output_root : String,
  timeout : Int,
) -> Unit {
  let cdp_port = choose_cdp_port()
  let target = cdp_port.to_string()
  let example_target_dir = dev_extension_example_target_dir(
    output_root, cdp_port,
  )
  @async.with_task_group(group => {
    let app = spawn_dev_extension_production_app(
      group, root, output_root, cdp_port,
    )
    let mut stopped = false
    defer {
      if !stopped {
        app.process.cancel()
      }
      remove_dev_extension_tree(example_target_dir)
    }
    ignore(
      wait_for_spawned_app_cdp(app, cdp_http_endpoint_from(target), timeout),
    )
    run_dev_extension_production_page_probe(group, app, target, timeout)
    match app_exit_code(app.process) {
      Some(code) =>
        fail(
          "production dev extension app exited before the probe completed: code=" +
          code.to_string() +
          app_output_suffix(app.output_path),
        )
      None => ()
    }
    let shutdown = finish_scenario_app(app, target)
    println(
      "MoonBit 47_dev_extension_js production shutdown passed: helpers=" +
      shutdown.helper_processes.to_string(),
    )
    stopped = true
  })
}

///|
async fn run_dev_extension_scenario_once(
  root : String,
  output_root : String,
  timeout : Int,
) -> Unit {
  let frontend = dev_extension_frontend_state(root)
  defer {
    if !frontend.had_node_modules {
      remove_dev_extension_tree(frontend.node_modules_dir)
    }
    if !frontend.had_dist {
      remove_dev_extension_tree(frontend.dist_dir)
    }
  }
  ensure_dev_extension_frontend(root, output_root, timeout)
  let frontend_port = choose_cdp_port()
  run_e2e_operation_with_timeout(
    timeout,
    "47_dev_extension_js development probe",
    () => {
      run_dev_extension_dev_probe_once(
        root, output_root, frontend_port, timeout,
      )
    },
  )
  build_dev_extension_frontend(root, output_root, timeout)
  run_e2e_operation_with_timeout(
    timeout,
    "47_dev_extension_js production probe",
    () => run_dev_extension_production_probe_once(root, output_root, timeout),
  )
}

///|
async fn run_dev_extension_scenario(root : String, timeout : Int) -> Unit {
  let output_root = @fs.tmpdir(prefix="proton-e2e-dev-extension-")
  defer remove_dev_extension_tree(output_root)
  install_scenario_helper(root, output_root)
  run_dev_extension_scenario_once(root, output_root, timeout)
}

///|
fn remove_dev_extension_tree(path : String) -> Unit {
  if !@mbfs.path_exists(path) {
    return
  }
  let is_dir = @mbfs.is_dir(path) catch { _ => return }
  if is_dir {
    let entries = @mbfs.read_dir(path) catch { _ => return }
    for entry in entries {
      remove_dev_extension_tree(join_path(path, entry))
    }
    @mbfs.remove_dir(path) catch {
      _ => ()
    }
  } else {
    @mbfs.remove_file(path) catch {
      _ => ()
    }
  }
}
