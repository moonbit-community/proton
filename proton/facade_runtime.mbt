///|
/// Runs the configured app through the native Proton runtime.
pub async fn App::run(self : App) -> Unit raise AppRunError {
  require_event_loop()
  match self.validation_error() {
    Some(error) => raise ConfigurationError(error)
    None => ()
  }
  let resolved = self.resolved_app_config()
  let browser_data_dir = resolve_browser_data_dir(resolved) catch {
    error => raise ConfigurationError(error)
  }
  let locale_preferences = resolve_locale_preferences(self.explicit_locale)
  let app_instance = match acquire_app_instance(resolved) {
    Some(@native.AppInstanceAcquire::Forwarded) => return
    Some(@native.AppInstanceAcquire::Primary(instance)) => Some(instance)
    None => None
  }
  {
    errdefer (match app_instance {
      Some(instance) => destroy_app_instance(instance) catch { _ => () }
      None => ()
    })
    run_manifest(
      resolved.manifest,
      resolved.permission_base_path,
      self.command_extensions,
      self.command_registrars,
      self.application_lifecycle_hooks,
      self.window_lifecycle_hooks,
      self.menu,
      self.bridge_startup_timeout_value_ms,
      self.resolved_headless(),
      locale_preferences,
      browser_data_dir?,
      application_name=resolved.application_name,
      app_instance~,
      launch_input_handlers=self.launch_input_handlers,
      planned_views=self.planned_views,
      window_event_handlers=self.window_event_handlers,
      view_event_handlers=self.view_event_handlers,
      window_close_handler=self.window_close_handler,
      navigation_handler=self.navigation_handler,
      popup_handler=self.popup_handler,
      download_handler=self.download_handler,
      certificate_handler=self.certificate_handler,
      media_handler=self.media_handler,
      download_event_handlers=self.download_event_handlers,
      update_channel=resolved.update_channel,
      update_handlers=self.update_handlers,
    )
  }
  match app_instance {
    Some(instance) => destroy_app_instance(instance)
    None => ()
  }
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
  permission_base_path : String,
  command_extensions : Map[String, @proton_command.AppCommandExtensionSpec],
  command_registrars : Array[(@proton_command.CommandRegistrar) -> Unit raise],
  application_lifecycle_hooks : Array[ApplicationLifecycleHook],
  window_lifecycle_hooks : Array[WindowLifecycleHook],
  menu : @native.MenuBar?,
  bridge_startup_timeout_ms : Int,
  headless : Bool,
  locale_preferences : @locale.LocalePreferences,
  browser_data_dir? : String,
  application_name? : String = "Proton",
  app_instance? : @native.AppInstance? = None,
  planned_views? : Array[(String, @native.ViewConfig)] = [],
  launch_input_handlers? : Array[async (RuntimeLaunchInput) -> Unit noraise] = [],
  window_event_handlers? : Array[
    async (WindowHandle, WindowEvent) -> Unit noraise,
  ] = [],
  view_event_handlers? : Array[async (ViewHandle, ViewEvent) -> Unit noraise] = [],
  window_close_handler? : (async (WindowHandle) -> WindowCloseDecision noraise)? = None,
  navigation_handler? : (async (BrowserHandle, NavigationRequest) -> NavigationDecision noraise)? = None,
  popup_handler? : (async (BrowserHandle, PopupRequest) -> PopupDecision noraise)? = None,
  download_handler? : (async (BrowserHandle, DownloadRequest) -> DownloadDecision noraise)? = None,
  certificate_handler? : (async (BrowserHandle, CertificateError) -> BrowserPermissionDecision noraise)? = None,
  media_handler? : (async (BrowserHandle, MediaPermissionRequest) -> BrowserPermissionDecision noraise)? = None,
  download_event_handlers? : Array[
    async (BrowserHandle, DownloadEvent) -> Unit noraise,
  ] = [],
  update_channel? : ResolvedUpdateChannel? = None,
  update_handlers? : Array[async (PendingUpdate) -> Unit noraise] = [],
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
  let catalog = framework_catalog(locale_preferences)
  let runtime = @native.Runtime::new(
    config=@native.RuntimeConfig::bundled(
      cache_dir?=browser_data_dir,
      locale=locale_preferences.chromium_locale(),
      accept_languages=locale_preferences.accept_languages(),
      remote_debugging_port=debug_port(manifest.debug),
      headless~,
    ).with_framework_dialog_labels(catalog.dialog_ok, catalog.dialog_cancel),
  ) catch {
    error => raise native_run_error("create runtime", error)
  }
  match app_instance {
    Some(instance) =>
      instance.attach_runtime(runtime) catch {
        error => {
          let attach_error = native_run_error("attach app instance", error)
          let failure = cleanup_run_error(
            Some(attach_error),
            app_cleanup(lifecycle, runtime, [], None),
          )
          match failure {
            Some(cleanup_error) => raise cleanup_error
            None => raise attach_error
          }
        }
      }
    None => ()
  }
  let mut command_host : CommandHostRuntime? = None
  let windows : Array[RunningWindow] = []
  let lifecycle_failures : Array[AppCleanupError] = []
  let wakeup = RuntimeWakeup::new()
  try {
    if !headless {
      match resolve_runtime_menu(menu, locale_preferences, application_name) {
        Some(menu) =>
          runtime.set_menu(menu) catch {
            error => raise native_run_error("set menu", error)
          }
        None => ()
      }
    }
    command_host = build_command_host(
      manifest,
      command_extensions,
      command_registrars~,
    )
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
    validate_registered_capabilities_have_grants(
      manifest, command_extensions, ops,
    ) catch {
      error => raise ConfigurationError(error)
    }
    let permission_policies : Array[WindowPermissionPolicy] = []
    for index, plan in plans {
      permission_policies.push(
        resolve_window_permission_policy(
          plan.id,
          policies[index],
          manifest,
          permission_base_path,
          command_extensions,
          ops,
        ) catch {
          error => raise ConfigurationError(error)
        },
      )
    }
    let bridge_enabled = ops.length() > 0 ||
      forward_menu_events ||
      window_lifecycle_hooks.length() > 0
    if bridge_enabled && !@native.bridge_permission_grants_supported() {
      raise UnsupportedNativeFeature(feature="bridge_permission_grants")
    }
    let definitions : Array[PreparedWindow] = []
    let browser_policy = @native.BrowserPolicy::new(
      navigation=if navigation_handler is Some(_) {
        @native.BrowserPolicyMode::Ask
      } else {
        @native.BrowserPolicyMode::Allow
      },
      popup=if popup_handler is Some(_) {
        @native.BrowserPolicyMode::Ask
      } else {
        @native.BrowserPolicyMode::Deny
      },
      download=if download_handler is Some(_) {
        @native.BrowserPolicyMode::Ask
      } else {
        @native.BrowserPolicyMode::Deny
      },
      certificate=if certificate_handler is Some(_) {
        @native.BrowserPolicyMode::Ask
      } else {
        @native.BrowserPolicyMode::Deny
      },
      media=if media_handler is Some(_) {
        @native.BrowserPolicyMode::Ask
      } else {
        @native.BrowserPolicyMode::Deny
      },
      devtools=manifest.debug > 0,
    )
    for index, plan in plans {
      let bridge = if bridge_enabled {
        let grants = permission_policies[index].native_grants(
          command_extensions,
        ) catch {
          error => raise ConfigurationError(error)
        }
        ensure_entry_bridge_grant(grants, policies[index])
        Some(native_bridge_config(grants))
      } else {
        None
      }
      definitions.push(PreparedWindow::{
        plan,
        bridge,
        permissions: permission_policies[index],
        browser_policy,
        views: if plan.id == "main" {
          planned_views
        } else {
          []
        },
      })
    }
    @async.with_task_group(application_tasks => {
      @async.with_task_group(window_tasks => {
        let session = RuntimeSession::new(
          runtime, locale_preferences, definitions, windows, command_host, wakeup,
          forward_menu_events, bridge_enabled, launch_input_handlers, window_event_handlers,
          window_tasks, view_event_handlers, window_close_handler, window_lifecycle_hooks,
          lifecycle_failures, bridge_startup_timeout_ms, navigation_handler, popup_handler,
          download_handler, certificate_handler, media_handler, download_event_handlers,
        )
        let application_context = ApplicationContext::new(
          application_tasks,
          session.window_manager(),
          locale_preferences,
        )
        let application_start = application_tasks.spawn(
          () => {
            defer session.wakeup.signal.notify()
            start_application_lifecycle_hooks(
              application_lifecycle_hooks, application_context, application_tasks,
              lifecycle_failures,
            )
          },
          no_wait=true,
          allow_failure=true,
        )
        session.drive_until_complete(application_start)
        active_update_channel.val = update_channel
        for definition in definitions {
          if definition.plan.open_on_start &&
            session.find_active_window(definition.plan.id) is None {
            ignore(session.create_window(definition))
          }
        }
        if bridge_enabled {
          session.wait_for_bridge_startup(bridge_startup_timeout_ms) catch {
            error => raise normalize_async_run_error(error)
          }
        }
        for running in windows {
          if !running.is_closed() {
            session.activate_window(running)
          }
        }
        lifecycle.begin_running()
        cleanup_previous_update()
        start_update_check(update_channel, update_handlers, application_tasks)
        session.run() catch {
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
        show_app_run_failure(
          runtime,
          preferred_active_window(windows).map(window => window.window),
          wakeup,
          primary,
          locale_preferences,
          lifecycle.has_reached_running(),
        ) catch {
          _ => ()
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
/// Persistent browser state is only safe when Proton owns the application's
/// single-instance route. Multi-instance runtimes receive native-owned
/// temporary profiles instead.
fn resolve_browser_data_dir(
  config : ResolvedAppConfig,
) -> String? raise AppConfigurationError {
  guard config.instance_identifier is Some(_) else { return None }
  guard config.application_identifier is Some(identifier) else {
    raise InvalidSetting(
      name="identifier",
      message="is required for persistent browser storage",
    )
  }
  let path = browser_data_dir(identifier) catch {
    error => raise InvalidSetting(name="identifier", message=error.message())
  }
  Some(path)
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
      open_on_start: true,
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
    plans.push(PlannedWindow::{
      id,
      window: window.window,
      entry: window.entry,
      open_on_start: window.open_on_start,
    })
  }
  plans
}

///|
fn native_window_config(
  window : @manifest.WindowManifest,
  bridge : @native.BridgeConfig?,
  browser : @native.BrowserPolicy,
  preferences : @locale.LocalePreferences,
) -> @native.WindowConfig {
  let catalog = framework_catalog(preferences)
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
    browser~,
    bridge?,
  ).with_framework_titlebar_labels(
    catalog.titlebar_minimize,
    catalog.titlebar_maximize,
    catalog.titlebar_restore,
    catalog.titlebar_close,
  )
}

///|
fn native_bridge_config(
  grants : Array[@native.BridgeGrantConfig],
) -> @native.BridgeConfig {
  @native.BridgeConfig::new(grants~)
}

///|
fn ensure_entry_bridge_grant(
  grants : Array[@native.BridgeGrantConfig],
  policy : BridgePagePolicy,
) -> Unit {
  let source_origin = match policy.entry_origin {
    Some(origin) => origin
    None => "app"
  }
  if !grants.any(grant => grant.source_origin == source_origin) {
    grants.push(@native.BridgeGrantConfig::new(source_origin, ops=[]))
  }
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
    EventLoopError(message) => EventLoopError(message)
    ConfigurationError(error) => ConfigurationError(error)
    NativeRuntimeError(action~, error~) => NativeRuntimeError(action~, error~)
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
fn refresh_bridge_startup_states(
  windows : Array[RunningWindow],
) -> @native.BridgeLifecycleState? raise AppRunError {
  let mut pending : @native.BridgeLifecycleState? = None
  for running in windows {
    if refresh_window_bridge_startup_state(running) {
      continue
    }
    if pending is None {
      pending = Some(
        running.window.bridge_lifecycle_state() catch {
          error =>
            raise native_run_error(
              "read bridge startup state for " + running.id,
              error,
            )
        },
      )
    }
  }
  pending
}

///|
fn refresh_window_bridge_startup_state(
  running : RunningWindow,
) -> Bool raise AppRunError {
  if running.bridge_ready {
    return true
  }
  if running.is_closed() {
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
    return false
  }
  match state.outcome {
    "ready" => {
      running.bridge_ready = true
      true
    }
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
    _ => false
  }
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
    EventLoopError(message) => message
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
    UnsupportedNativeFeature(feature~) =>
      "The active Proton native runtime is incompatible with this application.\n\nMissing feature: " +
      feature
    NativeRuntimeError(action~, error~) =>
      action + " failed: " + error.message()
    CommandExtensionLifecycleError(error) => error.message()
    LifecycleHookError(error) => error.message()
    UnexpectedTaskFailure(detail~) => detail
  }
}

///|
async fn show_runtime_failure_dialog(
  runtime : @native.Runtime,
  wakeup : RuntimeWakeup,
  detail : String,
  preferences : @locale.LocalePreferences,
  application_started : Bool,
) -> Unit {
  let (title, summary) = if application_started {
    (
      application_error_title(preferences),
      application_error_summary(preferences),
    )
  } else {
    (startup_failure_title(preferences), startup_failure_summary(preferences))
  }
  let message = framework_failure_message(summary, detail)
  let dialog = runtime.begin_message_dialog(
    Some(title),
    message,
    @native.DialogLevel::Error,
  ) catch {
    _ => return
  }
  while true {
    let revision = wakeup.revision()
    let completed = runtime.poll_message_dialog(dialog) catch { _ => return }
    match completed {
      true => return
      false => wakeup.wait_after(revision) catch { _ => return }
    }
  }
}

///|
async fn show_window_failure_dialog(
  window : @native.WindowRef,
  wakeup : RuntimeWakeup,
  detail : String,
  preferences : @locale.LocalePreferences,
) -> Bool {
  let message = framework_failure_message(
    application_error_summary(preferences),
    detail,
  )
  let dialog = window.begin_message_dialog(
    Some(application_error_title(preferences)),
    message,
    @native.DialogLevel::Error,
  ) catch {
    _ => return false
  }
  while true {
    let revision = wakeup.revision()
    let result = window.poll_dialog_result(dialog) catch { _ => return false }
    match result {
      @native.DialogPollResult::Ready(_) => return true
      @native.DialogPollResult::Pending =>
        wakeup.wait_after(revision) catch {
          _ => return false
        }
    }
  } nobreak {
    false
  }
}

///|
async fn show_app_run_failure(
  runtime : @native.Runtime,
  window : @native.Window?,
  wakeup : RuntimeWakeup,
  error : AppRunError,
  preferences : @locale.LocalePreferences,
  application_started : Bool,
) -> Unit {
  let message = app_run_error_dialog_text(error)
  if application_started {
    match window {
      Some(window) =>
        if show_window_failure_dialog(
            window.as_ref(),
            wakeup,
            message,
            preferences,
          ) {
          return
        }
      None => ()
    }
  }
  show_runtime_failure_dialog(
    runtime, wakeup, message, preferences, application_started,
  )
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
  handle : WindowHandle,
  windows : WindowManager,
  events : WindowEventEmitter,
  hooks : Array[WindowLifecycleHook],
  lifecycle_failures : Array[AppCleanupError],
  locale_preferences : @locale.LocalePreferences,
) -> Unit {
  @async.with_task_group(tasks => {
    start_window_lifecycle_hooks(
      hooks,
      WindowContext::new(
        running.id,
        handle,
        windows,
        tasks,
        events,
        locale_preferences,
      ),
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
fn is_stale_bridge_response_error(error : @native.NativeError) -> Bool {
  error.is_stale_bridge_response()
}
