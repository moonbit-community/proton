///|
/// Runs the configured app through the native Proton runtime.
pub async fn App::run(self : App) -> Unit raise AppRunError {
  guard app_runner_is_active() else {
    let message =
      #|Proton applications must be started with @proton.run from a synchronous main:
      #|
      #|fn main {
      #|  @proton.run(() => {
      #|    @proton.app().run_or_abort()
      #|  })
      #|}
      #|
      #|Do not call App::run directly from async fn main.
      #|
    raise RunnerError(message)
  }
  match self.validation_error() {
    Some(error) => raise ConfigurationError(error)
    None => ()
  }
  let resolved = self.resolved_app_config() catch {
    error => raise ConfigurationError(error)
  }
  run_manifest(
    resolved.manifest,
    self.command_extensions,
    self.command_registrars,
    self.application_lifecycle_hooks,
    self.window_lifecycle_hooks,
    self.menu,
    self.bridge_startup_timeout_value_ms,
    self.resolved_headless(),
    launch_input_handlers=self.launch_input_handlers,
  )
}

///|
/// Runs the configured app and aborts with the error message on failure.
pub async fn App::run_or_abort(self : App) -> Unit {
  self.run() catch {
    error => abort(error.message())
  }
}

///|
async fn run_manifest(
  manifest : @manifest.AppManifest,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
  command_registrars : Array[(@proton_command.CommandRegistrar) -> Unit raise],
  application_lifecycle_hooks : Array[ApplicationLifecycleHook],
  window_lifecycle_hooks : Array[WindowLifecycleHook],
  menu : @native.MenuBar?,
  bridge_startup_timeout_ms : Int,
  headless : Bool,
  launch_input_handlers? : Array[async (RuntimeLaunchInput) -> Unit noraise] = [],
) -> Unit raise AppRunError {
  let plans = planned_windows(manifest) catch {
    error => raise ConfigurationError(error)
  }
  if headless {
    for plan in plans {
      if plan.window.titlebar_style == @manifest.TitlebarStyle::Overlay {
        raise ConfigurationError(
          InvalidSetting(
            name="headless",
            message="titlebar overlay is not supported in headless mode",
          ),
        )
      }
    }
  }
  if headless && menu is Some(_) {
    raise ConfigurationError(
      InvalidSetting(
        name="headless",
        message="native menus are not supported in headless mode",
      ),
    )
  }
  let lifecycle = AppLifecycle::new()
  lifecycle.begin_starting()
  let forward_menu_events = menu is Some(_)
  let helper_path = bundled_runtime_helper_path()
  let runtime = @native.Runtime::new(
    config=@native.RuntimeConfig::bundled(
      helper_path?,
      remote_debugging_port=debug_port(manifest.debug),
      headless~,
    ),
  ) catch {
    error => raise native_run_error("create runtime", error)
  }
  let mut command_host : CommandHostRuntime? = None
  let windows : Array[RunningWindow] = []
  let lifecycle_failures : Array[AppCleanupError] = []
  let wakeup = RuntimeWakeup::new(runtime) catch {
    error => {
      let failure = cleanup_run_error(
        Some(error),
        app_cleanup(lifecycle, runtime, windows, None),
      )
      match failure {
        Some(cleanup_error) => raise cleanup_error
        None => raise error
      }
    }
  }
  defer wakeup.close()
  try {
    match menu {
      Some(menu) =>
        runtime.set_menu(menu) catch {
          error => raise native_run_error("set menu", error)
        }
      None => ()
    }
    command_host = build_command_host(
      manifest,
      command_extensions,
      command_registrars~,
    )
    @async.with_task_group(application_tasks => {
      let application_context = ApplicationContext::new(application_tasks)
      start_application_lifecycle_hooks(
        application_lifecycle_hooks, application_context, application_tasks, lifecycle_failures,
      )
      let frontend = build_bridge_frontend_config(manifest, command_extensions) catch {
        error => raise ConfigurationError(error)
      }
      let policies : Array[BridgePagePolicy] = []
      for plan in plans {
        let policy = bridge_page_policy_for_entry(plan.entry) catch {
          error => raise ConfigurationError(error)
        }
        policies.push(policy)
      }
      let ops = match command_host {
        Some(host) => host.host.registered_ops()
        None => []
      }
      let bridge_enabled = ops.length() > 0 ||
        frontend.extensions.length() > 0 ||
        frontend.initialization_units.length() > 0 ||
        forward_menu_events ||
        window_lifecycle_hooks.length() > 0
      @async.with_task_group(window_tasks => {
        let host = match command_host {
          Some(host) => Some(host.host)
          None => None
        }
        let pending : Array[BridgeDispatchTask] = []
        lifecycle.begin_window_create()
        for index, plan in plans {
          let bridge = if bridge_enabled {
            Some(native_bridge_config(ops, frontend, policies[index]))
          } else {
            None
          }
          let created_window = @native.Window::new(
            runtime,
            config=native_window_config(plan.window, bridge),
          ) catch {
            error => raise native_run_error("create window " + plan.id, error)
          }
          let running = RunningWindow::{
            id: plan.id,
            window: created_window,
            policy: policies[index],
            lifetime: WindowLifetime::new(),
            bridge_ready: false,
            closed: false,
          }
          windows.push(running)
          load_entry_after_create(created_window, plan.entry) catch {
            error => raise EntryLoadError(error)
          }
        }
        if bridge_enabled {
          wait_for_bridge_startup(
            runtime, windows, host, pending, wakeup, forward_menu_events, bridge_startup_timeout_ms,
            launch_input_handlers, window_tasks,
          ) catch {
            error => raise normalize_async_run_error(error)
          }
        }
        lifecycle.finish_window_create()
        for running in windows {
          if running.closed {
            continue
          }
          let window_events = WindowEventEmitter::new(
            typed_event_sender(running.window, None),
          )
          ignore(
            window_tasks.spawn(
              () => {
                run_window_lifecycle_scope(
                  running, window_events, window_lifecycle_hooks, lifecycle_failures,
                )
              },
              no_wait=true,
              allow_failure=true,
            ),
          )
          running.lifetime.wait_until_ready()
          if running.closed {
            continue
          }
          running.window.show() catch {
            error => raise native_run_error("show window " + running.id, error)
          }
        }
        lifecycle.begin_running()
        run_runtime_pump(
          runtime, windows, host, pending, wakeup, forward_menu_events, bridge_enabled,
          launch_input_handlers, window_tasks,
        ) catch {
          error => raise normalize_async_run_error(error)
        }
        lifecycle.observe_window_closed()
        window_tasks.return_immediately(())
      })
      application_tasks.return_immediately(())
    }) catch {
      error => raise normalize_async_run_error(error)
    }
  } catch {
    error => {
      let primary = normalize_async_run_error(error)
      if !headless {
        match windows.get(0) {
          Some(window) =>
            show_app_run_failure(runtime, window.window, wakeup, primary) catch {
              _ => ()
            }
          None =>
            show_runtime_failure_dialog(runtime, wakeup, primary.message()) catch {
              _ => ()
            }
        }
      }
      let failure = cleanup_run_error(
        Some(primary),
        app_cleanup(
          lifecycle,
          runtime,
          windows,
          command_host,
          lifecycle_failures~,
        ),
      )
      match failure {
        Some(cleanup_error) => raise cleanup_error
        None => raise primary
      }
    }
  }
  match
    cleanup_run_error(
      None,
      app_cleanup(
        lifecycle,
        runtime,
        windows,
        command_host,
        lifecycle_failures~,
      ),
    ) {
    Some(error) => raise error
    None => ()
  }
}

///|
fn planned_windows(
  manifest : @manifest.AppManifest,
) -> Array[PlannedWindow] raise AppConfigurationError {
  let plans = [
    PlannedWindow::{
      id: "main",
      window: manifest.window,
      entry: manifest.entry,
    },
  ]
  let ids : Map[String, Unit] = { "main": () }
  for window in manifest.windows {
    let id = window.id.trim().to_owned()
    guard id != "" else {
      raise InvalidSetting(name="windows.id", message="must not be empty")
    }
    guard !ids.contains(id) else {
      raise InvalidSetting(
        name="windows.id",
        message="duplicate window id: " + id,
      )
    }
    ids[id] = ()
    plans.push(PlannedWindow::{ id, window: window.window, entry: window.entry })
  }
  plans
}

///|
fn native_window_config(
  window : @manifest.WindowManifest,
  bridge : @native.BridgeConfig?,
) -> @native.WindowConfig {
  @native.WindowConfig::new(
    title=window.title,
    width=window.width,
    height=window.height,
    initial_url="about:blank",
    size_hint=match window.size_hint {
      @manifest.WindowSizeHint::None => @native.WindowSizeHint::Unconstrained
      @manifest.WindowSizeHint::Fixed => @native.WindowSizeHint::Fixed
      @manifest.WindowSizeHint::Min => @native.WindowSizeHint::Min
      @manifest.WindowSizeHint::Max => @native.WindowSizeHint::Max
    },
    titlebar_style=match window.titlebar_style {
      @manifest.TitlebarStyle::Default => @native.TitlebarStyle::Default
      @manifest.TitlebarStyle::Overlay => @native.TitlebarStyle::Overlay
    },
    bridge?,
  )
}

///|
fn native_bridge_config(
  ops : Array[String],
  frontend : BridgeFrontendConfig,
  policy : BridgePagePolicy,
) -> @native.BridgeConfig {
  let dev_origins = match policy.dev_origin {
    Some(origin) => [origin]
    None => []
  }
  @native.BridgeConfig::new(
    ops~,
    request_timeout_ms=policy.request_timeout_ms,
    dev_origins~,
    extensions=frontend.extensions,
    initialization_units=frontend.initialization_units,
  )
}

///|
fn native_run_error(
  action : String,
  error : @native.NativeError,
) -> AppRunError {
  NativeRuntimeError(action~, error~)
}

///|
fn normalize_async_run_error(error : Error) -> AppRunError {
  match error {
    RunnerError(message) => RunnerError(message)
    ConfigurationError(error) => ConfigurationError(error)
    NativeRuntimeError(action~, error~) => NativeRuntimeError(action~, error~)
    RuntimeWakeupError(error) => RuntimeWakeupError(error)
    CommandExtensionLifecycleError(error) =>
      CommandExtensionLifecycleError(error)
    LifecycleHookError(error) => LifecycleHookError(error)
    EntryLoadError(error) => EntryLoadError(error)
    BridgeStartupError(diagnostic) => BridgeStartupError(diagnostic)
    BridgeRuntimeError(diagnostic) => BridgeRuntimeError(diagnostic)
    CleanupFailed(primary~, failures~) => CleanupFailed(primary~, failures~)
    UnexpectedTaskFailure(detail~) => UnexpectedTaskFailure(detail~)
    _ => UnexpectedTaskFailure(detail=@debug.render(Repr(error)))
  }
}

///|
fn close_command_host(
  host : CommandHostRuntime?,
) -> Array[CommandExtensionLifecycleError] {
  match host {
    Some(value) => value.close()
    None => []
  }
}

///|
fn CommandHostRuntime::close(
  self : CommandHostRuntime,
) -> Array[CommandExtensionLifecycleError] {
  guard !self.closed else { return [] }
  let failures = close_command_host_runtime(self.host, self.destroy_hooks)
  self.closed = true
  failures
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
) -> @native.BridgeDiagnostic raise @native.NativeError {
  match window.take_bridge_failure() {
    Some(diagnostic) => diagnostic
    None =>
      bridge_protocol_diagnostic(
        state, "bridge_failure_missing_diagnostic", "renderer reported bridge failure without a diagnostic",
      )
  }
}

///|
async fn wait_for_bridge_startup(
  runtime : @native.Runtime,
  windows : Array[RunningWindow],
  host : @core.AppCommandHost?,
  pending : Array[BridgeDispatchTask],
  wakeup : RuntimeWakeup,
  forward_menu_events : Bool,
  timeout_ms : Int,
  launch_input_handlers : Array[async (RuntimeLaunchInput) -> Unit noraise],
  group : @async.TaskGroup[Unit],
) -> Unit raise AppRunError {
  let completed = @async.with_timeout_opt(timeout_ms, () => {
    while true {
      let did_work = pump_runtime_once(
        runtime,
        windows,
        host,
        pending,
        wakeup.signal,
        forward_menu_events,
        false,
        launch_input_handlers,
        group,
      )
      match refresh_bridge_startup_states(windows) {
        None => return
        Some(_) => if did_work { @async.sleep(0) } else { wakeup.wait() }
      }
    }
  }) catch {
    error => raise normalize_async_run_error(error)
  }
  match completed {
    Some(_) => ()
    None => {
      ignore(
        pump_runtime_once(
          runtime,
          windows,
          host,
          pending,
          wakeup.signal,
          forward_menu_events,
          false,
          launch_input_handlers,
          group,
        ),
      )
      match refresh_bridge_startup_states(windows) {
        None => return
        Some(state) =>
          raise BridgeStartupError(
            bridge_startup_timeout_diagnostic(state, timeout_ms),
          )
      }
    }
  }
}

///|
fn refresh_bridge_startup_states(
  windows : Array[RunningWindow],
) -> @native.BridgeLifecycleState? raise AppRunError {
  let mut pending : @native.BridgeLifecycleState? = None
  for running in windows {
    if running.bridge_ready {
      continue
    }
    if running.closed {
      raise EntryLoadError(ClosedDuringStartup)
    }
    let state = running.window.bridge_lifecycle_state() catch {
      error =>
        raise native_run_error(
          "read bridge startup state for " + running.id,
          error,
        )
    }
    if state.url == "about:blank" {
      if pending is None {
        pending = Some(state)
      }
      continue
    }
    match state.outcome {
      "ready" => running.bridge_ready = true
      "failed" =>
        try bridge_failure(running.window, state) catch {
          error =>
            raise native_run_error(
              "read bridge startup failure for " + running.id,
              error,
            )
        } noraise {
          diagnostic => raise BridgeStartupError(diagnostic)
        }
      "ineligible" =>
        raise BridgeStartupError(
          bridge_protocol_diagnostic(
            state, "bridge_entry_origin_ineligible", "the application entry is not eligible for the native bridge",
          ),
        )
      _ => if pending is None { pending = Some(state) }
    }
  }
  pending
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
    RunnerError(message) => message
    BridgeStartupError(diagnostic) =>
      "The application could not finish starting its native bridge.\n\nError code: " +
      diagnostic.code
    BridgeRuntimeError(diagnostic) =>
      "The application bridge stopped working.\n\nError code: " +
      diagnostic.code
    CleanupFailed(primary~, failures~) =>
      cleanup_failure_message(primary, failures)
    EntryLoadError(error) => error.message()
    ConfigurationError(error) => error.message()
    NativeRuntimeError(action~, error~) =>
      action + " failed: " + error.message()
    RuntimeWakeupError(error) => error.message()
    CommandExtensionLifecycleError(error) => error.message()
    LifecycleHookError(error) => error.message()
    UnexpectedTaskFailure(detail~) => detail
  }
}

///|
async fn show_runtime_failure_dialog(
  runtime : @native.Runtime,
  wakeup : RuntimeWakeup,
  message : String,
) -> Unit {
  let dialog = runtime.begin_message_dialog(
    Some("Application Startup Failed"),
    message,
    @native.DialogLevel::Error,
  ) catch {
    _ => return
  }
  while true {
    let completed = runtime.poll_message_dialog(dialog) catch { _ => return }
    match completed {
      true => return
      false => wakeup.wait() catch { _ => return }
    }
  }
}

///|
async fn show_window_failure_dialog(
  window : @native.WindowRef,
  wakeup : RuntimeWakeup,
  message : String,
) -> Unit {
  let dialog = window.begin_message_dialog(
    Some("Application Error"),
    message,
    @native.DialogLevel::Error,
  ) catch {
    _ => return
  }
  while true {
    let revision = wakeup.signal.revision()
    let result = window.poll_dialog_result(dialog) catch { _ => return }
    match result {
      @native.DialogPollResult::Ready(_) => return
      @native.DialogPollResult::Pending =>
        // The main pump is no longer running on this error path, so this
        // waiter must consume the native pipe itself.
        if wakeup.signal.revision() == revision {
          wakeup.wait() catch {
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
      show_window_failure_dialog(window.as_ref(), wakeup, message)
    _ => show_runtime_failure_dialog(runtime, wakeup, message)
  }
}

///|
async fn run_runtime_pump(
  runtime : @native.Runtime,
  windows : Array[RunningWindow],
  host : @core.AppCommandHost?,
  pending : Array[BridgeDispatchTask],
  wakeup : RuntimeWakeup,
  forward_menu_events : Bool,
  monitor_bridge : Bool,
  launch_input_handlers : Array[async (RuntimeLaunchInput) -> Unit noraise],
  group : @async.TaskGroup[Unit],
) -> Unit raise AppRunError {
  while !all_windows_closed(windows) {
    let did_work = pump_runtime_once(
      runtime,
      windows,
      host,
      pending,
      wakeup.signal,
      forward_menu_events,
      monitor_bridge,
      launch_input_handlers,
      group,
    )
    if did_work {
      @async.sleep(0) catch {
        error => raise normalize_async_run_error(error)
      }
    } else {
      wakeup.wait() catch {
        error => raise normalize_async_run_error(error)
      }
    }
  }
  cancel_all_bridge_tasks(pending)
}

///|
fn take_runtime_bridge_failure(
  window : @native.Window,
) -> @native.BridgeDiagnostic? raise @native.NativeError {
  let state = window.bridge_lifecycle_state()
  if !state.failure_pending {
    return None
  }
  Some(bridge_failure(window, state))
}

///|
fn pump_runtime_once(
  runtime : @native.Runtime,
  windows : Array[RunningWindow],
  host : @core.AppCommandHost?,
  pending : Array[BridgeDispatchTask],
  wake_signal : @core.RuntimeWakeSignal,
  forward_menu_events : Bool,
  monitor_bridge : Bool,
  launch_input_handlers : Array[async (RuntimeLaunchInput) -> Unit noraise],
  group : @async.TaskGroup[Unit],
) -> Bool raise AppRunError {
  let mut did_work = false

  let mut polling_events = true
  while polling_events {
    let next_event = runtime.poll_event() catch {
      error => raise native_run_error("poll event", error)
    }
    match next_event {
      None => polling_events = false
      Some(event) => {
        did_work = true
        dispatch_runtime_event(
          event, windows, forward_menu_events, launch_input_handlers, group,
        )
        cancel_bridge_request_task(pending, event.bridge_request_cancellation())
        if event.is_window_closed() {
          cancel_window_bridge_tasks(pending, event.window_id())
        }
      }
    }
  }

  if monitor_bridge {
    for running in windows {
      if !running.closed {
        let failure = take_runtime_bridge_failure(running.window) catch {
          error =>
            raise native_run_error(
              "read bridge failure for " + running.id,
              error,
            )
        }
        match failure {
          Some(diagnostic) => raise BridgeRuntimeError(diagnostic)
          None => ()
        }
      }
    }
  }

  let mut polling_bridge = true
  while polling_bridge {
    let next_request = runtime.poll_bridge_request() catch {
      error => raise native_run_error("poll bridge request", error)
    }
    match next_request {
      None => polling_bridge = false
      Some(request) => {
        did_work = true
        let request_id = request.request_id()
        let target = match find_running_window(windows, request.window()) {
          Some(window) if !window.closed => window
          _ => {
            runtime.respond_bridge_request(
              @native.BridgeResponse::Err(
                request_id~,
                code="window_closed",
                message="the issuing window is no longer available",
              ),
            ) catch {
              error =>
                if !is_stale_bridge_response_error(error) {
                  raise native_run_error("reject bridge request", error)
                }
            }
            continue
          }
        }
        match host {
          None =>
            runtime.respond_bridge_request(
              @native.BridgeResponse::Err(
                request_id~,
                code="command_host_unavailable",
                message="the application command host is not available",
              ),
            ) catch {
              error =>
                if !is_stale_bridge_response_error(error) {
                  raise native_run_error("reject bridge request", error)
                }
            }
          Some(host) => {
            let task = group.spawn(
              () => {
                defer wake_signal.notify()
                dispatch_bridge_request(
                  target.window,
                  host,
                  request,
                  target.policy,
                  wake_signal,
                )
              },
              no_wait=true,
              allow_failure=true,
            )
            pending.push(BridgeDispatchTask::{
              request_id,
              window: target.window.id(),
              task,
              state: Running,
            })
          }
        }
      }
    }
  }

  let remaining : Array[BridgeDispatchTask] = []
  for item in pending {
    if item.state == Cancelled {
      continue
    }
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
        item.state = Responding
        runtime.respond_bridge_request(response) catch {
          error =>
            if is_stale_bridge_response_error(error) {
              item.state = Stale
            } else {
              raise native_run_error("respond bridge request", error)
            }
        }
        if item.state == Responding {
          item.state = Completed
        }
      }
      None => remaining.push(item)
    }
  }
  pending.clear()
  for item in remaining {
    pending.push(item)
  }
  did_work
}

///|
fn cancel_all_bridge_tasks(pending : Array[BridgeDispatchTask]) -> Unit {
  for item in pending {
    if item.state == Running {
      item.task.cancel()
      item.state = Cancelled
    }
  }
  pending.clear()
}

///|
fn dispatch_runtime_event(
  event : @native.RuntimeEvent,
  windows : Array[RunningWindow],
  forward_menu_events : Bool,
  launch_input_handlers : Array[async (RuntimeLaunchInput) -> Unit noraise],
  group : @async.TaskGroup[Unit],
) -> Unit raise AppRunError {
  dispatch_internal_runtime_event(event)
  if event.is_window_closed() {
    mark_window_closed(windows, event.window_id())
  }
  dispatch_launch_input(event, launch_input_handlers, group)
  if forward_menu_events {
    if event.menu_command_id() is Some(command_id) {
      forward_menu_command_to_window(windows, command_id, event.window_id())
    }
  }
}

///|
fn dispatch_internal_runtime_event(event : @native.RuntimeEvent) -> Unit {
  match event.notification_result() {
    Some(result) => publish_notification_result(result)
    None => ()
  }
}

///|
fn dispatch_launch_input(
  event : @native.RuntimeEvent,
  handlers : Array[async (RuntimeLaunchInput) -> Unit noraise],
  group : @async.TaskGroup[Unit],
) -> Unit {
  match event.launch_input() {
    Some(input) =>
      for handler in handlers {
        ignore(group.spawn(() => handler(input), no_wait=true))
      }
    None => ()
  }
}

///|
fn find_running_window(
  windows : Array[RunningWindow],
  window_id : Int64,
) -> RunningWindow? {
  for running in windows {
    if running.window.id() == window_id {
      return Some(running)
    }
  }
  None
}

///|
fn mark_window_closed(
  windows : Array[RunningWindow],
  window_id : Int64?,
) -> Unit {
  match window_id {
    Some(window_id) =>
      match find_running_window(windows, window_id) {
        Some(window) => {
          window.closed = true
          window.lifetime.close()
        }
        None => ()
      }
    None => ()
  }
}

///|
fn WindowLifetime::new() -> WindowLifetime {
  WindowLifetime::{
    ready: false,
    closed: false,
    startup_error: None,
    ready_signal: @async.CondVar::Cond(),
    close_signal: @async.CondVar::Cond(),
  }
}

///|
fn WindowLifetime::finish_start(
  self : WindowLifetime,
  error : AppRunError?,
) -> Unit {
  if !self.ready {
    self.startup_error = error
    self.ready = true
    self.ready_signal.broadcast()
  }
}

///|
async fn WindowLifetime::wait_until_ready(
  self : WindowLifetime,
) -> Unit raise AppRunError {
  while !self.ready {
    self.ready_signal.wait() catch {
      error => raise normalize_async_run_error(error)
    }
  }
  match self.startup_error {
    Some(error) => raise error
    None => ()
  }
}

///|
fn WindowLifetime::close(self : WindowLifetime) -> Unit {
  if !self.closed {
    self.closed = true
    self.close_signal.broadcast()
  }
}

///|
async fn WindowLifetime::wait_until_closed(self : WindowLifetime) -> Unit {
  while !self.closed {
    self.close_signal.wait()
  }
}

///|
async fn run_window_lifecycle_scope(
  running : RunningWindow,
  events : WindowEventEmitter,
  hooks : Array[WindowLifecycleHook],
  lifecycle_failures : Array[AppCleanupError],
) -> Unit {
  @async.with_task_group(tasks => {
    start_window_lifecycle_hooks(
      hooks,
      WindowContext::new(running.id, running.window.as_ref(), tasks, events),
      tasks,
      lifecycle_failures,
    ) catch {
      error => {
        running.lifetime.finish_start(Some(normalize_async_run_error(error)))
        tasks.return_immediately(())
        return
      }
    }
    running.lifetime.finish_start(None)
    running.lifetime.wait_until_closed()
    tasks.return_immediately(())
  }) catch {
    error =>
      running.lifetime.finish_start(Some(normalize_async_run_error(error)))
  }
}

///|
fn all_windows_closed(windows : Array[RunningWindow]) -> Bool {
  windows.all(fn(window) { window.closed })
}

///|
fn cancel_window_bridge_tasks(
  pending : Array[BridgeDispatchTask],
  window_id : Int64?,
) -> Unit {
  match window_id {
    Some(window_id) =>
      for item in pending {
        if item.window == window_id && item.state == Running {
          item.task.cancel()
          item.state = Cancelled
        }
      }
    None => ()
  }
}

///|
fn cancel_bridge_request_task(
  pending : Array[BridgeDispatchTask],
  request_id : Int64?,
) -> Unit {
  match request_id {
    Some(request_id) =>
      for item in pending {
        if item.request_id == request_id && item.state == Running {
          item.task.cancel()
          item.state = Cancelled
        }
      }
    None => ()
  }
}

///|
fn forward_menu_command_to_window(
  windows : Array[RunningWindow],
  command_id : String,
  focused_window : Int64?,
) -> Unit raise AppRunError {
  let target = match focused_window {
    Some(window_id) => find_running_window(windows, window_id)
    None => None
  }
  let target = match target {
    Some(window) => Some(window)
    None => windows.get(0)
  }
  match target {
    Some(window) if !window.closed =>
      forward_menu_command(window.window, command_id, focused_window)
    _ => ()
  }
}

///|
fn is_stale_bridge_response_error(error : @native.NativeError) -> Bool {
  error.is_stale_bridge_response()
}
