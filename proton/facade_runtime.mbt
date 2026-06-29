///|
/// Runs the configured app through the native Proton runtime.
pub async fn App::run(self : App) -> Result[Unit, String] {
  @async.sleep(0)
  match self.validation_error() {
    Some(error) => return Err(error)
    None => ()
  }
  match self.resolved_manifest() {
    Err(error) => Err(error)
    Ok(manifest) =>
      run_manifest(
        manifest,
        self.command_extensions,
        app_config_base_dir(self.file_path),
      )
  }
}

///|
/// Runs the configured app and aborts with the error message on failure.
pub async fn App::run_or_abort(self : App) -> Unit {
  match self.run() {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}

///|
async fn run_manifest(
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
  base_dir : String?,
) -> Result[Unit, String] {
  let helper_path = macos_bundled_helper_path()
  let runtime = match
    @native.Runtime::new(
      config=@native.RuntimeConfig::bundled(
        helper_path?,
        remote_debugging_port=debug_port(manifest.debug),
      ),
    ) {
    Ok(runtime) => runtime
    Err(error) => return Err(native_error_message("create runtime", error))
  }
  let window = match
    @native.Window::new(
      runtime,
      config=@native.WindowConfig::new(
        title=manifest.window.title,
        width=manifest.window.width,
        height=manifest.window.height,
        initial_url="about:blank",
      ),
    ) {
    Ok(window) => window
    Err(error) => {
      ignore(runtime.destroy())
      return Err(native_error_message("create window", error))
    }
  }

  let command_host = match
    build_command_host(manifest, command_extensions, base_dir) {
    Err(error) => {
      ignore(window.destroy())
      ignore(runtime.destroy())
      return Err(error)
    }
    Ok(host) => host
  }
  let command_proxy_script = match
    build_command_proxy_script(manifest, command_extensions) {
    Err(error) => {
      close_command_host(command_host)
      ignore(window.destroy())
      ignore(runtime.destroy())
      return Err(error)
    }
    Ok(script) => script
  }
  match command_host {
    Some(host) => {
      let ops = host.registered_ops()
      match
        native_unit_result(
          "install bridge",
          window.install_bridge(@native.BridgeConfig::new(ops~)),
        ) {
        Err(error) => {
          host.close()
          ignore(window.destroy())
          ignore(runtime.destroy())
          return Err(error)
        }
        Ok(_) => install_extension_event_sender(window, host)
      }
    }
    None => ()
  }
  match load_entry_after_create(window, manifest.entry, command_proxy_script) {
    Err(error) => {
      close_command_host(command_host)
      ignore(window.destroy())
      ignore(runtime.destroy())
      Err(error)
    }
    Ok(_) =>
      match native_unit_result("show window", window.show()) {
        Err(error) => {
          close_command_host(command_host)
          ignore(window.destroy())
          ignore(runtime.destroy())
          Err(error)
        }
        Ok(_) => {
          let run_result = match command_host {
            Some(host) => run_bridge_pump(runtime, window, host)
            None => run_window_pump(runtime)
          }
          close_command_host(command_host)
          let destroy_result = native_unit_result(
            "destroy runtime",
            runtime.destroy(),
          )
          match run_result {
            Err(error) => Err(error)
            Ok(_) => destroy_result
          }
        }
      }
  }
}

///|
fn app_config_base_dir(file_path : String?) -> String? {
  match file_path {
    Some(path) => Some((path : @mbpath.Path).dirname().to_string())
    None => None
  }
}

///|
fn close_command_host(host : @core.AppCommandHost?) -> Unit {
  match host {
    Some(value) => value.close()
    None => ()
  }
}

///|
async fn run_window_pump(runtime : @native.Runtime) -> Result[Unit, String] {
  let mut closed = false
  let mut idle_delay = 0
  let mut runtime_wait_supported = true
  while !closed {
    let mut did_work = false
    match runtime.do_message_loop_work() {
      Err(error) => return Err(native_error_message("pump runtime", error))
      Ok(_) => ()
    }

    let mut polling_events = true
    while polling_events {
      match runtime.poll_event() {
        Err(error) => return Err(native_error_message("poll event", error))
        Ok(None) => polling_events = false
        Ok(Some(event)) => {
          did_work = true
          if event.is_window_closed() {
            closed = true
          }
        }
      }
    }

    if did_work {
      idle_delay = 0
      @async.sleep(0)
    } else {
      match wait_for_runtime_idle(runtime, idle_delay, runtime_wait_supported) {
        Err(error) => return Err(error)
        Ok((next_delay, next_wait_supported)) => {
          idle_delay = next_delay
          runtime_wait_supported = next_wait_supported
        }
      }
    }
  }
  Ok(())
}

///|
async fn run_bridge_pump(
  runtime : @native.Runtime,
  window : @native.Window,
  host : @core.AppCommandHost,
) -> Result[Unit, String] {
  @async.with_task_group(group => {
    let mut closed = false
    let mut idle_delay = 0
    let mut runtime_wait_supported = true
    let mut pending : Array[BridgeDispatchTask] = []
    while !closed {
      let mut did_work = false
      match runtime.do_message_loop_work() {
        Err(error) => return Err(native_error_message("pump runtime", error))
        Ok(_) => ()
      }

      let mut polling_events = true
      while polling_events {
        match runtime.poll_event() {
          Err(error) => return Err(native_error_message("poll event", error))
          Ok(None) => polling_events = false
          Ok(Some(event)) => {
            did_work = true
            if event.is_window_closed() {
              closed = true
            }
          }
        }
      }

      let mut polling_bridge = true
      while polling_bridge {
        match runtime.poll_bridge_request() {
          Err(error) =>
            return Err(native_error_message("poll bridge request", error))
          Ok(None) => polling_bridge = false
          Ok(Some(request)) => {
            did_work = true
            let request_id = request.request_id()
            let task = group.spawn(
              () => dispatch_bridge_request(window, host, request),
              no_wait=true,
              allow_failure=true,
            )
            pending.push(BridgeDispatchTask::{ request_id, task })
          }
        }
      }

      let remaining : Array[BridgeDispatchTask] = []
      for item in pending {
        let completed = item.task.try_wait() catch {
          _ =>
            Some(
              @native.BridgeResponse::Err(
                request_id=item.request_id,
                code="handler_failed",
                message="bridge handler task failed",
              ),
            )
        }
        match completed {
          Some(response) => {
            did_work = true
            match runtime.respond_bridge_request(response) {
              Err(error) =>
                if !is_stale_bridge_response_error(error) {
                  return Err(
                    native_error_message("respond bridge request", error),
                  )
                }
              Ok(_) => ()
            }
          }
          None => remaining.push(item)
        }
      }
      pending = remaining

      if did_work {
        idle_delay = 0
        @async.sleep(0)
      } else if pending.length() > 0 {
        idle_delay = 0
        @async.sleep(1)
      } else {
        match
          wait_for_runtime_idle(runtime, idle_delay, runtime_wait_supported) {
          Err(error) => return Err(error)
          Ok((next_delay, next_wait_supported)) => {
            idle_delay = next_delay
            runtime_wait_supported = next_wait_supported
          }
        }
      }
    }
    for item in pending {
      item.task.cancel()
    }
    Ok(())
  })
}

///|
async fn wait_for_runtime_idle(
  runtime : @native.Runtime,
  idle_delay : Int,
  runtime_wait_supported : Bool,
) -> Result[(Int, Bool), String] {
  if runtime_wait_supported {
    match runtime.wait(interest_mask=@native.runtime_wait_all, timeout_ms=16) {
      Ok(_) => Ok((0, true))
      Err(error) =>
        if is_runtime_wait_unsupported(error) {
          sleep_with_idle_backoff(idle_delay).map(fn(next_delay) {
            (next_delay, false)
          })
        } else {
          Err(native_error_message("wait runtime", error))
        }
    }
  } else {
    sleep_with_idle_backoff(idle_delay).map(fn(next_delay) {
      (next_delay, false)
    })
  }
}

///|
async fn sleep_with_idle_backoff(idle_delay : Int) -> Result[Int, String] {
  let delay = next_idle_delay(idle_delay)
  @async.sleep(delay)
  Ok(delay)
}

///|
fn is_runtime_wait_unsupported(error : @native.NativeError) -> Bool {
  error.status == proton_err_unsupported
}

///|
let proton_err_unsupported = -8

///|
fn is_stale_bridge_response_error(error : @native.NativeError) -> Bool {
  (error.status == -2 && error.message.contains("no longer pending")) ||
  (
    error.status == -7 &&
    error.message.contains("failed to send bridge response to renderer")
  )
}

///|
fn next_idle_delay(current : Int) -> Int {
  if current <= 0 {
    1
  } else if current >= 16 {
    16
  } else {
    let next = current * 2
    if next > 16 {
      16
    } else {
      next
    }
  }
}
