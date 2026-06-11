///|
priv struct FrameworkIpcLaunchConfig {
  ws : @ipc_ws.WsIpcLaunchConfig
}

///|
priv struct FrameworkIpcChild {
  process : @process.Process
}

///|
fn make_framework_ipc_launch_config(
  ipc_token : String?,
) -> Result[FrameworkIpcLaunchConfig, String] {
  let ws = match ipc_token {
    Some(token) => @ipc_ws.WsIpcLaunchConfig::auto_with_token(token)
    None => Ok(@ipc_ws.WsIpcLaunchConfig::auto())
  }
  ws.map(fn(ws) { FrameworkIpcLaunchConfig::{ ws, } })
}

///|
fn framework_ipc_launch_config_from_ws(
  ws : @ipc_ws.WsIpcLaunchConfig,
) -> FrameworkIpcLaunchConfig {
  FrameworkIpcLaunchConfig::{ ws, }
}

///|
fn framework_ipc_launch_config_ws(
  config : FrameworkIpcLaunchConfig,
) -> @ipc_ws.WsIpcLaunchConfig {
  config.ws
}

///|
/// The final path component of `command`, accepting both separators so a
/// Windows path keeps its file name on any host.
fn command_file_name(command : String) -> String {
  let mut name = command[:]
  for part in command.split("/") {
    name = part
  }
  let tail = name.to_owned()
  let mut file = tail[:]
  for part in tail.split("\\") {
    file = part
  }
  file.to_owned()
}

///|
/// Redirect the framework child's stdio to files. The files live in the
/// framework's working directory when the caller provides one — the command
/// itself may sit somewhere read-only (a signed macOS bundle under App
/// Translocation is mounted read-only), where writing next to the executable
/// would abort the whole launch. Without a cwd (dev runs from a writable
/// checkout) they stay command-adjacent. Names are stable per command, so a
/// relaunch truncates the previous run's files instead of accumulating.
async fn prepare_framework_stdio(
  command : String,
  dir? : String,
) -> (&@process.ProcessInput, &@process.ProcessOutput, &@process.ProcessOutput) {
  let base = if dir is Some(dir) {
    dir + "/" + command_file_name(command)
  } else {
    command
  }
  let stdin_path = base + ".framework.stdin"
  let stdout_path = base + ".framework.stdout.log"
  let stderr_path = base + ".framework.stderr.log"
  @mbfs.write_string_to_file(stdin_path, "")
  @mbfs.write_string_to_file(stdout_path, "")
  @mbfs.write_string_to_file(stderr_path, "")
  (
    @process.redirect_from_file(stdin_path),
    @process.redirect_to_file(stdout_path),
    @process.redirect_to_file(stderr_path),
  )
}

///|
async fn[X] spawn_framework_process_in_group(
  group : @async.TaskGroup[X],
  command : String,
  args? : Array[String] = [],
  cwd? : String,
) -> Result[FrameworkIpcChild, String] {
  try {
    let (stdin, stdout, stderr) = prepare_framework_stdio(command, dir?=cwd)
    let child = match cwd {
      Some(cwd) =>
        @process.spawn(
          group,
          command,
          args,
          stdin~,
          stdout~,
          stderr~,
          cwd~,
          cancel_handler=@process.graceful_cancel(timeout=1000),
          no_wait=true,
        )
      None =>
        @process.spawn(
          group,
          command,
          args,
          stdin~,
          stdout~,
          stderr~,
          cancel_handler=@process.graceful_cancel(timeout=1000),
          no_wait=true,
        )
    }
    Ok(FrameworkIpcChild::{ process: child })
  } catch {
    err => Err(err.to_string())
  }
}

///|
async fn wait_framework_ipc_ready(
  config : FrameworkIpcLaunchConfig,
) -> Result[Int, String] {
  @ipc_ws.wait_ws_ipc_ready(config.ws)
}

///|
fn make_framework_ipc_bridge_script(
  config : FrameworkIpcLaunchConfig,
  op_names : Array[String],
) -> String {
  @ipc_ws.make_ws_ipc_bridge_script(config.ws, op_names)
}

///|
fn FrameworkIpcChild::cancel(self : FrameworkIpcChild) -> Unit {
  self.process.cancel()
}

///|
async fn FrameworkIpcChild::wait(self : FrameworkIpcChild) -> Int {
  self.process.wait()
}

///|
async fn run_framework_ipc_command_host_with_config(
  host : @core.AppCommandHost,
  config : FrameworkIpcLaunchConfig,
) -> Result[Unit, String] {
  host.seal_registrations()
  match
    @ipc_ws.run_ws_ipc_server_with_event_sink(
      config.ws,
      async fn(request) { host.dispatch_ipc(request) },
      event_sink=fn(emit) { host.set_event_sender(emit) },
    ) {
    Ok(_) => {
      host.close()
      Ok(())
    }
    Err(message) => {
      host.close()
      Err("app command host stopped: " + message)
    }
  }
}
