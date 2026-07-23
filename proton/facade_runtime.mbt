///|
/// Runs the configured app through the native Proton runtime.
pub async fn App::run(self : App) -> Unit raise AppRunError {
  match self.validation_error() {
    Some(error) => raise ConfigurationError(error)
    None => ()
  }
  match self.resolved_app_config() {
    Err(error) => raise ConfigurationError(error)
    Ok(resolved) =>
      run_manifest(
        resolved.manifest,
        self.command_extensions,
        resolved.base_dir,
        self.menu,
        self.bridge_startup_timeout_value_ms,
      )
  }
}

///|
/// Runs the configured app and aborts with the error message on failure.
pub async fn App::run_or_abort(self : App) -> Unit {
  self.run() catch {
    error => abort(app_run_error_text(error))
  }
}

///|
fn app_run_error_text(error : AppRunError) -> String {
  match error {
    ConfigurationError(message) =>
      "application configuration failed: " + message
    NativeRuntimeError(error) =>
      "native runtime failed (" +
      error.status.to_string() +
      "): " +
      error.message
    EntryLoadError(message) => "application entry failed to load: " + message
    BridgeStartupError(diagnostic) =>
      "application startup failed [" +
      diagnostic.code +
      "]: " +
      diagnostic.message +
      "\n" +
      @debug.render(@debug.to_repr(diagnostic))
    BridgeRuntimeError(diagnostic) =>
      "application bridge failed [" +
      diagnostic.code +
      "]: " +
      diagnostic.message +
      "\n" +
      @debug.render(@debug.to_repr(diagnostic))
  }
}

///|
async fn run_manifest(
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
  base_dir : String?,
  menu : @native.MenuBar?,
  bridge_startup_timeout_ms : Int,
) -> Unit raise AppRunError {
  let forward_menu_events = menu is Some(_)
  let helper_path = macos_bundled_helper_path() catch {
    error => raise normalize_async_run_error(error)
  }
  let runtime = match
    @native.Runtime::new(
      config=@native.RuntimeConfig::bundled(
        helper_path?,
        remote_debugging_port=debug_port(manifest.debug),
      ),
    ) {
    Ok(runtime) => runtime
    Err(error) => raise native_run_error("create runtime", error)
  }
  let wakeup = RuntimeWakeup::new(runtime) catch {
    error => {
      ignore(runtime.destroy())
      raise error
    }
  }
  defer wakeup.close()
  match menu {
    Some(menu) =>
      match runtime.set_menu(menu) {
        Err(error) => {
          ignore(runtime.destroy())
          raise native_run_error("set menu", error)
        }
        Ok(_) => ()
      }
    None => ()
  }
  let command_host = match
    build_command_host(manifest, command_extensions, base_dir) {
    Err(error) => {
      ignore(runtime.destroy())
      raise ConfigurationError(error)
    }
    Ok(host) => host
  }
  let frontend = match
    build_bridge_frontend_config(manifest, command_extensions) {
    Err(error) => {
      close_command_host(command_host)
      ignore(runtime.destroy())
      raise ConfigurationError(error)
    }
    Ok(script) => script
  }
  let bridge_policy = match bridge_page_policy_for_manifest(manifest) {
    Err(error) => {
      close_command_host(command_host)
      ignore(runtime.destroy())
      raise ConfigurationError(error)
    }
    Ok(policy) => policy
  }
  let ops = match command_host {
    Some(host) => host.host.registered_ops()
    None => []
  }
  let bridge = if ops.length() > 0 ||
    frontend.extensions.length() > 0 ||
    frontend.initialization_units.length() > 0 ||
    forward_menu_events {
    Some(
      @native.BridgeConfig::new(
        ops~,
        dev_origins=bridge_page_policy_dev_origins(bridge_policy),
        extensions=frontend.extensions,
        initialization_units=frontend.initialization_units,
      ),
    )
  } else {
    None
  }
  let window = match
    @native.Window::new(
      runtime,
      config=@native.WindowConfig::new(
        title=manifest.window.title,
        width=manifest.window.width,
        height=manifest.window.height,
        initial_url="about:blank",
        bridge?,
      ),
    ) {
    Ok(window) => window
    Err(error) => {
      close_command_host(command_host)
      ignore(runtime.destroy())
      raise native_run_error("create window", error)
    }
  }
  match command_host {
    Some(host) => install_extension_event_sender(window, host.host)
    None => ()
  }
  try {
    match load_entry_after_create(window, manifest.entry) {
      Err(error) => raise EntryLoadError(error)
      Ok(_) => ()
    }
    if bridge is Some(_) {
      wait_for_bridge_startup(
        runtime, window, wakeup, forward_menu_events, bridge_startup_timeout_ms,
      ) catch {
        error => raise normalize_async_run_error(error)
      }
    }
    match window.show() {
      Err(error) => raise native_run_error("show window", error)
      Ok(_) => ()
    }
    match command_host {
      Some(host) =>
        run_bridge_pump(
          runtime,
          window,
          host.host,
          bridge_policy,
          wakeup,
          forward_menu_events,
        ) catch {
          error => raise normalize_async_run_error(error)
        }
      None =>
        run_window_pump(
          runtime,
          window,
          wakeup,
          forward_menu_events,
          bridge is Some(_),
        ) catch {
          error => raise normalize_async_run_error(error)
        }
    }
  } catch {
    error => {
      show_app_run_failure(runtime, window, wakeup, error) catch {
        _ => ()
      }
      close_command_host(command_host)
      ignore(window.destroy())
      ignore(runtime.destroy())
      raise error
    }
  }
  close_command_host(command_host)
  match runtime.destroy() {
    Err(error) => raise native_run_error("destroy runtime", error)
    Ok(_) => ()
  }
}

///|
fn native_run_error(
  action : String,
  error : @native.NativeError,
) -> AppRunError {
  NativeRuntimeError({
    status: error.status,
    message: action + " failed: " + error.message,
  })
}

///|
fn normalize_async_run_error(error : Error) -> AppRunError {
  match error {
    ConfigurationError(message) => ConfigurationError(message)
    NativeRuntimeError(error) => NativeRuntimeError(error)
    EntryLoadError(message) => EntryLoadError(message)
    BridgeStartupError(diagnostic) => BridgeStartupError(diagnostic)
    BridgeRuntimeError(diagnostic) => BridgeRuntimeError(diagnostic)
    _ =>
      NativeRuntimeError({
        status: -6,
        message: "application task failed: " +
        @debug.render(@debug.to_repr(error)),
      })
  }
}

///|
fn close_command_host(host : CommandHostRuntime?) -> Unit {
  match host {
    Some(value) => value.close()
    None => ()
  }
}

///|
fn CommandHostRuntime::close(self : CommandHostRuntime) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  close_command_host_runtime(self.host, self.destroy_hooks)
}

///|
fn bridge_protocol_diagnostic(
  state : @native.BridgeLifecycleState,
  code : String,
  message : String,
) -> @native.BridgeDiagnostic {
  @native.BridgeDiagnostic::{
    abi_version: 1,
    stage: "prepare",
    code,
    message,
    page_instance: state.page_instance,
    url: state.url,
    owner: None,
    source_url: None,
    source_line: None,
    line: None,
    column: None,
    stack: None,
    additional_failure_count: None,
    details_truncated: false,
  }
}

///|
fn bridge_failure(
  window : @native.Window,
  state : @native.BridgeLifecycleState,
) -> Result[@native.BridgeDiagnostic, @native.NativeError] {
  window
  .take_bridge_failure()
  .map(fn(failure) {
    match failure {
      Some(diagnostic) => diagnostic
      None =>
        bridge_protocol_diagnostic(
          state, "bridge_failure_missing_diagnostic", "renderer reported bridge failure without a diagnostic",
        )
    }
  })
}

///|
async fn wait_for_bridge_startup(
  runtime : @native.Runtime,
  window : @native.Window,
  wakeup : RuntimeWakeup,
  forward_menu_events : Bool,
  timeout_ms : Int,
) -> Unit raise AppRunError {
  let completed = @async.with_timeout_opt(timeout_ms, () => {
    wait_for_bridge_startup_until_terminal(
      runtime, window, wakeup, forward_menu_events,
    )
  }) catch {
    error => raise normalize_async_run_error(error)
  }
  match completed {
    Some(_) => ()
    None => {
      let state = pump_bridge_startup_once(runtime, window, forward_menu_events)
      if bridge_startup_is_ready(state) {
        return
      }
      raise BridgeStartupError(
        bridge_startup_timeout_diagnostic(state, timeout_ms),
      )
    }
  }
}

///|
async fn wait_for_bridge_startup_until_terminal(
  runtime : @native.Runtime,
  window : @native.Window,
  wakeup : RuntimeWakeup,
  forward_menu_events : Bool,
) -> Unit {
  while true {
    let state = pump_bridge_startup_once(runtime, window, forward_menu_events)
    if bridge_startup_is_ready(state) {
      return
    }
    wakeup.wait(runtime)
  }
}

///|
fn pump_bridge_startup_once(
  runtime : @native.Runtime,
  window : @native.Window,
  forward_menu_events : Bool,
) -> @native.BridgeLifecycleState raise AppRunError {
  match runtime.do_message_loop_work() {
    Err(error) => raise native_run_error("pump runtime during startup", error)
    Ok(_) => ()
  }
  let mut polling_events = true
  while polling_events {
    match runtime.poll_event() {
      Err(error) => raise native_run_error("poll startup event", error)
      Ok(None) => polling_events = false
      Ok(Some(event)) => {
        if event.is_window_closed() {
          raise EntryLoadError("window closed before startup completed")
        }
        if forward_menu_events {
          if event.menu_command_id() is Some(command_id) {
            forward_menu_command(window, command_id, event.window_id())
          }
        }
      }
    }
  }
  let state = match window.bridge_lifecycle_state() {
    Err(error) => raise native_run_error("read bridge startup state", error)
    Ok(state) => state
  }
  if state.url != "about:blank" {
    match state.outcome {
      "failed" =>
        match bridge_failure(window, state) {
          Err(error) =>
            raise native_run_error("read bridge startup failure", error)
          Ok(diagnostic) => raise BridgeStartupError(diagnostic)
        }
      "ineligible" =>
        raise BridgeStartupError(
          bridge_protocol_diagnostic(
            state, "bridge_entry_origin_ineligible", "the application entry is not eligible for the native bridge",
          ),
        )
      _ => ()
    }
  }
  state
}

///|
fn bridge_startup_is_ready(state : @native.BridgeLifecycleState) -> Bool {
  state.url != "about:blank" && state.outcome == "ready"
}

///|
fn bridge_startup_timeout_diagnostic(
  state : @native.BridgeLifecycleState,
  timeout_ms : Int,
) -> @native.BridgeDiagnostic {
  bridge_protocol_diagnostic(
    state,
    "bridge_startup_timeout",
    "the native bridge did not become ready within " +
    timeout_ms.to_string() +
    " ms",
  )
}

///|
fn app_run_error_dialog_text(error : AppRunError) -> String {
  match error {
    BridgeStartupError(diagnostic) =>
      "The application could not finish starting its native bridge.\n\nError code: " +
      diagnostic.code
    BridgeRuntimeError(diagnostic) =>
      "The application bridge stopped working.\n\nError code: " +
      diagnostic.code
    EntryLoadError(message) => message
    ConfigurationError(message) => message
    NativeRuntimeError(error) => error.message
  }
}

///|
async fn show_runtime_failure_dialog(
  runtime : @native.Runtime,
  wakeup : RuntimeWakeup,
  message : String,
) -> Unit {
  let dialog = match
    runtime.begin_message_dialog(
      Some("Application Startup Failed"),
      message,
      @native.DialogLevel::Error,
    ) {
    Err(_) => return
    Ok(dialog) => dialog
  }
  while true {
    ignore(runtime.do_message_loop_work())
    match runtime.poll_message_dialog(dialog) {
      Err(_) => return
      Ok(true) => return
      Ok(false) => wakeup.wait(runtime) catch { _ => return }
    }
  }
}

///|
async fn show_window_failure_dialog(
  runtime : @native.Runtime,
  window : @native.WindowRef,
  wakeup : RuntimeWakeup,
  message : String,
) -> Unit {
  let dialog = match
    window.begin_message_dialog(
      Some("Application Error"),
      message,
      @native.DialogLevel::Error,
    ) {
    Err(_) => return
    Ok(dialog) => dialog
  }
  while true {
    let revision = wakeup.signal.revision()
    match window.poll_dialog_result(dialog) {
      Err(_) => return
      Ok(@native.DialogPollResult::Ready(_)) => return
      Ok(@native.DialogPollResult::Pending) =>
        // The main pump is no longer running on this error path, so this
        // waiter must consume the native pipe itself.
        if wakeup.signal.revision() == revision {
          wakeup.wait(runtime) catch {
            _ => return
          }
        }
    }
  }
}

///|
async fn show_app_run_failure(
  runtime : @native.Runtime,
  window : @native.Window,
  wakeup : RuntimeWakeup,
  error : AppRunError,
) -> Unit {
  let message = app_run_error_dialog_text(error)
  match error {
    BridgeRuntimeError(_) =>
      show_window_failure_dialog(runtime, window.as_ref(), wakeup, message)
    _ => show_runtime_failure_dialog(runtime, wakeup, message)
  }
}

///|
async fn run_window_pump(
  runtime : @native.Runtime,
  window : @native.Window,
  wakeup : RuntimeWakeup,
  forward_menu_events : Bool,
  monitor_bridge : Bool,
) -> Unit raise AppRunError {
  let mut closed = false
  while !closed {
    let mut did_work = false
    match runtime.do_message_loop_work() {
      Err(error) => raise native_run_error("pump runtime", error)
      Ok(_) => ()
    }

    let mut polling_events = true
    while polling_events {
      match runtime.poll_event() {
        Err(error) => raise native_run_error("poll event", error)
        Ok(None) => polling_events = false
        Ok(Some(event)) => {
          did_work = true
          if event.is_window_closed() {
            closed = true
          }
          if forward_menu_events {
            if event.menu_command_id() is Some(command_id) {
              forward_menu_command(window, command_id, event.window_id())
            }
          }
        }
      }
    }

    if monitor_bridge {
      match take_runtime_bridge_failure(window) {
        Err(error) => raise native_run_error("read bridge failure", error)
        Ok(Some(diagnostic)) => raise BridgeRuntimeError(diagnostic)
        Ok(None) => ()
      }
    }

    if did_work {
      @async.sleep(0) catch {
        error => raise normalize_async_run_error(error)
      }
    } else {
      wakeup.wait(runtime) catch {
        error => raise normalize_async_run_error(error)
      }
    }
  }
}

///|
fn take_runtime_bridge_failure(
  window : @native.Window,
) -> Result[@native.BridgeDiagnostic?, @native.NativeError] {
  let state = match window.bridge_lifecycle_state() {
    Err(error) => return Err(error)
    Ok(state) => state
  }
  if !state.failure_pending {
    return Ok(None)
  }
  bridge_failure(window, state).map(fn(diagnostic) { Some(diagnostic) })
}

///|
async fn run_bridge_pump(
  runtime : @native.Runtime,
  window : @native.Window,
  host : @core.AppCommandHost,
  policy : BridgePagePolicy,
  wakeup : RuntimeWakeup,
  forward_menu_events : Bool,
) -> Unit raise AppRunError {
  @async.with_task_group(group => {
    let mut closed = false
    let mut pending : Array[BridgeDispatchTask] = []
    while !closed {
      let mut did_work = false
      match runtime.do_message_loop_work() {
        Err(error) => raise native_run_error("pump runtime", error)
        Ok(_) => ()
      }

      let mut polling_events = true
      while polling_events {
        match runtime.poll_event() {
          Err(error) => raise native_run_error("poll event", error)
          Ok(None) => polling_events = false
          Ok(Some(event)) => {
            did_work = true
            if event.is_window_closed() {
              closed = true
            }
            if forward_menu_events {
              if event.menu_command_id() is Some(command_id) {
                forward_menu_command(window, command_id, event.window_id())
              }
            }
          }
        }
      }

      match take_runtime_bridge_failure(window) {
        Err(error) => raise native_run_error("read bridge failure", error)
        Ok(Some(diagnostic)) => raise BridgeRuntimeError(diagnostic)
        Ok(None) => ()
      }

      let mut polling_bridge = true
      while polling_bridge {
        match runtime.poll_bridge_request() {
          Err(error) => raise native_run_error("poll bridge request", error)
          Ok(None) => polling_bridge = false
          Ok(Some(request)) => {
            did_work = true
            let request_id = request.request_id()
            let task = group.spawn(
              () => {
                defer wakeup.signal.notify()
                dispatch_bridge_request(
                  window,
                  host,
                  request,
                  policy,
                  wakeup.signal,
                )
              },
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
                  raise native_run_error("respond bridge request", error)
                }
              Ok(_) => ()
            }
          }
          None => remaining.push(item)
        }
      }
      pending = remaining

      if did_work {
        @async.sleep(0)
      } else {
        wakeup.wait(runtime)
      }
    }
    for item in pending {
      item.task.cancel()
    }
  }) catch {
    error => raise normalize_async_run_error(error)
  }
}

///|
fn is_stale_bridge_response_error(error : @native.NativeError) -> Bool {
  (error.status == -2 && error.message.contains("no longer pending")) ||
  (
    error.status == -7 &&
    error.message.contains("failed to send bridge response to renderer")
  )
}
