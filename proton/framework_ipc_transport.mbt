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
async fn[X] spawn_framework_process_in_group(
  group : @async.TaskGroup[X],
  command : String,
  args? : Array[String] = [],
  cwd? : String,
) -> Result[FrameworkIpcChild, String] {
  try {
    let child = match cwd {
      Some(cwd) =>
        @process.spawn(
          group,
          command,
          args,
          cwd~,
          cancel_handler=@process.graceful_cancel(timeout=1000),
          no_wait=true,
        )
      None =>
        @process.spawn(
          group,
          command,
          args,
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
