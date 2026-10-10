///|
fn RuntimeSession::RuntimeSession(
  config : ResolvedAppConfig,
  environment : RuntimeEnvironment,
  updates : ApplicationUpdates,
  close_coordinator : CloseCoordinator,
  runtime : @native.Runtime,
  event_pump : RuntimeEventPump,
  definitions : Array[PreparedWindow],
  windows : Array[RunningWindow],
  command_host : CommandHostRuntime?,
  wakeup : RuntimeWakeup,
  forward_menu_events : Bool,
  monitor_bridge : Bool,
  app_instance : @native.AppInstance?,
  application_tasks : @async.TaskGroup[Unit],
  window_tasks : @async.TaskGroup[Unit],
  lifecycle_failures : Array[AppCleanupError],
) -> RuntimeSession {
  RuntimeSession::{
    config,
    environment,
    updates,
    runtime,
    event_pump,
    definitions,
    windows,
    has_created_window: windows.length() > 0,
    command_host,
    pending_bridge: [],
    wakeup,
    forward_menu_events,
    monitor_bridge,
    application_tasks,
    window_tasks,
    lifecycle_failures,
    app_instance,
    window_commands: [],
    pending_window_opens: [],
    pending_browser_requests: [],
    pending_resource_requests: [],
    close_coordinator,
  }
}

///|
fn CloseCoordinator::CloseCoordinator() -> CloseCoordinator {
  CloseCoordinator::{
    state: CloseRunning,
    pending: [],
    pending_quit: None,
    purpose: Quit(0),
    relaunch_scheduled: false,
    last_window_quit_handled: false,
  }
}

///|
/// Owns the purpose and priority of one exit transaction.
fn CloseCoordinator::begin_exit(
  self : CloseCoordinator,
  purpose : ExitPurpose,
) -> Bool {
  match purpose {
    ForceExit(_) => {
      guard self.state != CloseCommitted else { return false }
    }
    Quit(_) | InstallUpdate => {
      guard self.state == CloseRunning && !self.is_forced() else {
        return false
      }
      guard purpose != InstallUpdate || !self.relaunch_scheduled else {
        return false
      }
      self.state = CloseBeforeQuit
    }
  }
  self.purpose = purpose
  true
}

///|
fn CloseCoordinator::is_quitting(self : CloseCoordinator) -> Bool {
  self.state != CloseRunning || self.is_forced()
}

///|
fn CloseCoordinator::find(
  self : CloseCoordinator,
  window_id : Int64,
) -> PendingCloseDecision? {
  for pending in self.pending {
    if pending.window == window_id {
      return Some(pending)
    }
  }
  None
}

///|
fn CloseCoordinator::cancel(
  self : CloseCoordinator,
  window_id : Int64?,
) -> Unit {
  let remaining : Array[PendingCloseDecision] = []
  for pending in self.pending {
    if window_id == Some(pending.window) {
      pending.task.cancel()
    } else {
      remaining.push(pending)
    }
  }
  self.pending.clear()
  for pending in remaining {
    self.pending.push(pending)
  }
}

///|
fn CloseCoordinator::cancel_all(self : CloseCoordinator) -> Unit {
  for pending in self.pending {
    pending.task.cancel()
  }
  self.pending.clear()
  match self.pending_quit {
    Some(task) => {
      task.cancel()
      self.pending_quit = None
    }
    None => ()
  }
}

///|
fn RuntimeSession::window_manager(self : RuntimeSession) -> WindowManager {
  WindowManager::{
    open_window: id => self.request_open_window(id),
    find_window: id => {
      self.find_active_window(id).map(window => self.window_handle(window))
    },
  }
}

///|
fn RuntimeSession::application_context(
  self : RuntimeSession,
) -> ApplicationContext {
  ApplicationContext(
    updates=self.updates,
    session=self.session_handle(),
    close_coordinator=self.close_coordinator,
    self.application_tasks,
    self.window_manager(),
    self.environment.locale_preferences,
    request_quit=exit_code => self.request_quit(exit_code),
    request_exit=exit_code => self.request_exit(exit_code),
    request_update_install=() => self.request_update_install(),
    has_single_instance_lock=() => self.has_single_instance_lock(),
    release_single_instance_lock=() => self.release_single_instance_lock(),
    application_identifier=self.config.application_identifier,
    application_executable=self.environment.application_executable,
    application_arguments=self.environment.application_arguments,
    url_schemes=self.config.url_schemes,
  )
}

///|
fn RuntimeSession::window_handle(
  self : RuntimeSession,
  window : RunningWindow,
) -> WindowHandle {
  { session: self, id: window.id, native_id: window.native_id, }
}

///|
fn RuntimeSession::view_handle(
  self : RuntimeSession,
  window : RunningWindow,
  view : RunningView,
) -> ViewHandle {
  {
    session: self,
    id: view.id,
    native_id: view.native_id,
    window_id: window.id,
    window_native_id: window.native_id,
  }
}

///|
/// Resolves a live view instance by window id, view id, and both native
/// instance ids. The pair of ids keeps stale handles from targeting a later
/// view or window that reuses the same declarative id.
fn RuntimeSession::resolve_view(
  self : RuntimeSession,
  window_id : String,
  window_native_id : Int64,
  view_id : String,
  view_native_id : Int64,
) -> RunningView raise WindowSessionError {
  let running = self.resolve_window(window_id, window_native_id)
  for view in running.views {
    if view.id == view_id && view.view.id() != 0 {
      if view.view.id() != view_native_id {
        raise StaleView(id=view_id)
      }
      return view
    }
  }
  raise UnknownView(id=view_id)
}

///|
fn ViewHandle::with_view(
  self : ViewHandle,
  action : String,
  operation : (@native.View) -> Unit raise @native.NativeError,
) -> Unit raise WindowSessionError {
  let running = self.session.resolve_view(
    self.window_id,
    self.window_native_id,
    self.id,
    self.native_id,
  )
  operation(running.view) catch {
    error =>
      raise window_operation_failed(
        action + " view " + self.id + " in window " + self.window_id,
        error,
      )
  }
}

///|
fn RuntimeSession::add_window_view(
  self : RuntimeSession,
  window_id : String,
  window_native_id : Int64,
  view_id : String,
  config : @native.ViewConfig,
) -> ViewHandle raise WindowSessionError {
  let running = self.resolve_window(window_id, window_native_id)
  let running_view = add_view_to_running_window(running, view_id, config)
  self.emit_web_contents_created(
    self.view_handle(running, running_view).web_contents(),
  )
  self.view_handle(running, running_view)
}

///|
fn add_view_to_running_window(
  running : RunningWindow,
  view_id : String,
  config : @native.ViewConfig,
) -> RunningView raise WindowSessionError {
  if view_id.is_empty() {
    raise window_operation_failed(
      "add view to window " + running.id,
      @native.NativeError::InvalidArgument(message="view id must not be empty"),
    )
  }
  for view in running.views {
    if view.id == view_id && view.view.id() != 0 {
      raise AlreadyExists(id=view_id)
    }
  }
  let created = @native.View::View(running.window, config) catch {
    error =>
      raise window_operation_failed(
        "add view " + view_id + " to window " + running.id,
        error,
      )
  }
  let running_view = RunningView::{
    id: view_id,
    native_id: created.id(),
    view: created,
    document: None,
    observed_loading: None,
  }
  running.views.push(running_view)
  running_view
}

///|
fn RuntimeSession::remove_window_view(
  self : RuntimeSession,
  window_id : String,
  window_native_id : Int64,
  view_id : String,
) -> Unit raise WindowSessionError {
  let running = self.resolve_window(window_id, window_native_id)
  for view in running.views {
    if view.id == view_id && view.view.id() != 0 {
      view.view.destroy() catch {
        error =>
          raise window_operation_failed(
            "remove view " + view_id + " from window " + window_id,
            error,
          )
      }
      self.cancel_contents_browser_requests(
        running.native_id,
        Some(view.native_id),
      )
      // Keep the event recipient until the native close notification arrives.
      return
    }
  }
  raise UnknownView(id=view_id)
}

///|
fn RuntimeSession::list_window_views(
  self : RuntimeSession,
  window_id : String,
  window_native_id : Int64,
) -> Array[ViewHandle] {
  match self.find_active_window(window_id) {
    Some(running) if running.native_id == window_native_id =>
      running.views
      .filter(view => view.view.id() != 0)
      .map(view => self.view_handle(running, view))
    _ => []
  }
}

///|
fn RuntimeSession::find_window_view(
  self : RuntimeSession,
  window_id : String,
  window_native_id : Int64,
  view_id : String,
) -> ViewHandle? {
  match self.find_active_window(window_id) {
    Some(running) if running.native_id == window_native_id =>
      for view in running.views {
        if view.id == view_id && view.view.id() != 0 {
          return Some(self.view_handle(running, view))
        }
      } nobreak {
        None
      }
    _ => None
  }
}

///|
fn RuntimeSession::browser_handle(
  self : RuntimeSession,
  window : RunningWindow,
) -> WebContentsHandle {
  {
    session: self,
    id: window.id,
    native_id: window.native_id,
    target: PrimaryPage,
  }
}

///|
fn PdfPrintOptions::to_native(
  self : PdfPrintOptions,
) -> @native.PdfPrintSettings {
  let (margin_type, margin_top, margin_right, margin_bottom, margin_left) = match
    self.margins {
    PdfPrintMargins::Default => (0, 0.0, 0.0, 0.0, 0.0)
    PdfPrintMargins::NoMargins => (1, 0.0, 0.0, 0.0, 0.0)
    PdfPrintMargins::Custom(top~, right~, bottom~, left~) =>
      (2, top, right, bottom, left)
  }
  {
    landscape: self.landscape,
    print_background: self.print_background,
    scale: self.scale,
    paper_width: self.paper_width,
    paper_height: self.paper_height,
    prefer_css_page_size: self.prefer_css_page_size,
    margin_type,
    margin_top,
    margin_right,
    margin_bottom,
    margin_left,
    page_ranges: self.page_ranges,
    display_header_footer: self.display_header_footer,
    header_template: self.header_template,
    footer_template: self.footer_template,
    generate_tagged_pdf: self.generate_tagged_pdf,
    generate_document_outline: self.generate_document_outline,
  }
}

///|
fn RuntimeSession::session_handle(self : RuntimeSession) -> SessionHandle {
  let runtime = self.runtime
  let completions = self.event_pump.cookie_completions
  SessionHandle::{
    read_cookies: (url, include_http_only) => {
      let request_id = runtime.cookie_begin_get(url, include_http_only) catch {
        error => raise session_operation_failed("read cookies", error)
      }
      cookies_from_native(completions.wait(request_id))
    },
    write_cookie: (url, name, value, domain, path, secure, http_only, same_site) => {
      runtime.cookie_set(
        url,
        name,
        value,
        domain?,
        path?,
        secure~,
        http_only~,
        same_site=same_site.to_native(),
      ) catch {
        error => raise session_operation_failed("set cookie", error)
      }
    },
    remove_cookies: (url, name) => {
      runtime.cookie_delete(url, name) catch {
        error => raise session_operation_failed("delete cookies", error)
      }
    },
    flush_cookie_store: () => {
      runtime.cookie_flush() catch {
        error => raise session_operation_failed("flush cookies", error)
      }
    },
    clear_http_cache: () => {
      runtime.clear_cache() catch {
        error => raise session_operation_failed("clear cache", error)
      }
    },
    clear_http_auth_cache: () => {
      runtime.clear_auth_cache() catch {
        error => raise session_operation_failed("clear auth cache", error)
      }
    },
    clear_certificate_exceptions: () => {
      runtime.clear_certificate_exceptions() catch {
        error =>
          raise session_operation_failed("clear certificate exceptions", error)
      }
    },
    close_all_connections: () => {
      runtime.close_all_connections() catch {
        error => raise session_operation_failed("close connections", error)
      }
    },
    clear_storage_data: kind => {
      try {
        match kind {
          Cookies | AllSupported => {
            runtime.cookie_delete(None, None)
            runtime.cookie_flush()
          }
          HttpCache => ()
        }
        match kind {
          HttpCache | AllSupported => runtime.clear_cache()
          Cookies => ()
        }
      } catch {
        error => raise session_operation_failed("clear storage", error)
      }
    },
  }
}

///|
fn RunningWindow::is_active(self : RunningWindow) -> Bool {
  match self.state {
    WindowStarting | WindowOpen => true
    WindowCloseRequested | WindowClosed => false
  }
}

///|
fn RunningWindow::is_closed(self : RunningWindow) -> Bool {
  self.state is WindowClosed
}

///|
fn preferred_active_window(windows : Array[RunningWindow]) -> RunningWindow? {
  preferred_active_windows(windows).get(0)
}

///|
fn preferred_active_windows(
  windows : Array[RunningWindow],
) -> Array[RunningWindow] {
  let candidates : Array[RunningWindow] = []
  let fallback : Array[RunningWindow] = []
  for running in windows {
    if running.is_active() {
      if running.id == "main" {
        candidates.push(running)
      } else {
        fallback.push(running)
      }
    }
  }
  for running in fallback {
    candidates.push(running)
  }
  candidates
}

///|
fn RuntimeSession::close_window(
  self : RuntimeSession,
  id : String,
  native_id : Int64,
) -> Unit raise WindowSessionError {
  let running = self.resolve_window(id, native_id)
  running.window.close() catch {
    error => raise window_operation_failed("close window " + id, error)
  }
  if self.config.window_close_handler is None {
    running.state = WindowCloseRequested
  }
}

///|
fn RuntimeSession::resolve_window(
  self : RuntimeSession,
  id : String,
  native_id : Int64,
) -> RunningWindow raise WindowSessionError {
  match self.find_active_window(id) {
    Some(window) if window.native_id == native_id => window
    _ => raise StaleWindow(id~)
  }
}

///|
fn WindowHandle::with_window(
  self : WindowHandle,
  action : String,
  operation : (@native.Window) -> Unit raise @native.NativeError,
) -> Unit raise WindowSessionError {
  let running = self.session.resolve_window(self.id, self.native_id)
  operation(running.window) catch {
    error => raise window_operation_failed(action + " window " + self.id, error)
  }
}

///|
fn RuntimeSession::load_window_html(
  self : RuntimeSession,
  id : String,
  native_id : Int64,
  html : String,
  base_url : String,
) -> Unit raise WindowSessionError {
  let running = self.resolve_window(id, native_id)
  guard resource_document_url_is_supported(base_url) else {
    raise window_operation_failed(
      "load HTML in window " + id,
      @native.NativeError::InvalidArgument(
        message="base_url must use a Proton application origin",
      ),
    )
  }
  let previous = running.document
  running.document = Some({ url: base_url, content: @utf8.encode(html), })
  running.window.load_url(base_url) catch {
    error => {
      running.document = previous
      raise window_operation_failed("load HTML in window " + id, error)
    }
  }
}

///|
fn RuntimeSession::load_view_html(
  self : RuntimeSession,
  window_id : String,
  window_native_id : Int64,
  view_id : String,
  view_native_id : Int64,
  html : String,
  base_url : String,
) -> Unit raise WindowSessionError {
  let running = self.resolve_view(
    window_id, window_native_id, view_id, view_native_id,
  )
  guard resource_document_url_is_supported(base_url) else {
    raise window_operation_failed(
      "load HTML in view " + view_id + " in window " + window_id,
      @native.NativeError::InvalidArgument(
        message="base_url must use a Proton application origin",
      ),
    )
  }
  let previous = running.document
  running.document = Some({ url: base_url, content: @utf8.encode(html), })
  running.view.load_url(base_url) catch {
    error => {
      running.document = previous
      raise window_operation_failed(
        "load HTML in view " + view_id + " in window " + window_id,
        error,
      )
    }
  }
}

///|
fn RuntimeSession::read_window_state(
  self : RuntimeSession,
  id : String,
  native_id : Int64,
) -> WindowState raise WindowSessionError {
  let running = self.resolve_window(id, native_id)
  WindowState::from_native(running.window.state()) catch {
    error =>
      raise window_operation_failed("read window " + id + " state", error)
  }
}

///|
fn RuntimeSession::read_window_content_size(
  self : RuntimeSession,
  id : String,
  native_id : Int64,
) -> (Int, Int) raise WindowSessionError {
  let running = self.resolve_window(id, native_id)
  running.window.content_size() catch {
    error =>
      raise window_operation_failed("read content size of window " + id, error)
  }
}

///|
fn RuntimeSession::set_window_parent(
  self : RuntimeSession,
  id : String,
  native_id : Int64,
  parent_native_id : Int64?,
  modal : Bool,
) -> Unit raise WindowSessionError {
  let running = self.resolve_window(id, native_id)
  let parent = match parent_native_id {
    Some(parent_id) => {
      let mut found : RunningWindow? = None
      for candidate in self.windows {
        if candidate.is_active() && candidate.native_id == parent_id {
          found = Some(candidate)
          break
        }
      }
      match found {
        Some(parent) => Some(parent.window.as_ref())
        None => raise StaleWindow(id="parent")
      }
    }
    None => None
  }
  running.window.set_parent(parent, modal) catch {
    error => raise window_operation_failed("set parent of window " + id, error)
  }
}

///|
fn RuntimeSession::find_definition(
  self : RuntimeSession,
  id : String,
) -> PreparedWindow? {
  for definition in self.definitions {
    if definition.plan.id == id {
      return Some(definition)
    }
  }
  None
}

///|
fn RuntimeSession::find_active_window(
  self : RuntimeSession,
  id : String,
) -> RunningWindow? {
  for running in self.windows {
    if running.id == id && running.is_active() {
      return Some(running)
    }
  }
  None
}

///|
fn RuntimeSession::create_window(
  self : RuntimeSession,
  definition : PreparedWindow,
) -> RunningWindow raise AppRunError {
  let plan = definition.plan
  if self.find_active_window(plan.id) is Some(_) {
    raise ConfigurationError(
      InvalidSetting(
        name="window.id",
        message="window is already open: " + plan.id,
      ),
    )
  }
  let created_window = @native.Window::Window(
    self.runtime,
    config=native_window_config(
      plan.window,
      definition.bridge,
      definition.browser_policy,
      self.environment.locale_preferences,
      self.config.web_request_cancel_prefixes,
      self.config.web_request_redirect_prefixes,
      self.config.web_request_header_prefixes,
    ),
  ) catch {
    error => raise native_run_error("create window " + plan.id, error)
  }
  let (document, asset_root) = match definition.entry {
    RemoteEntry(_) => (None, None)
    DocumentEntry(document, asset_root) => (Some(document), asset_root)
  }
  let running = RunningWindow::{
    id: plan.id,
    native_id: created_window.id(),
    window: created_window,
    permissions: definition.permissions,
    lifetime: WindowLifetime(),
    views: [],
    document,
    asset_root,
    bridge_ready: !self.monitor_bridge,
    state: WindowStarting,
    observed_state: None,
    observed_browser_loading: None,
  }
  errdefer (created_window.destroy() catch {
    error =>
      self.lifecycle_failures.push(
        WindowDestroy(status=error.status(), detail=error.message()),
      )
  })
  if self.config.window_close_handler is Some(_) {
    created_window.set_close_interception(true) catch {
      error =>
        raise native_run_error(
          "enable close interception for " + plan.id,
          error,
        )
    }
  }
  load_prepared_entry(created_window, definition.entry) catch {
    error => raise EntryLoadError(error)
  }
  for view_plan in definition.views {
    let (view_id, view_config) = view_plan
    ignore(
      add_view_to_running_window(running, view_id, view_config) catch {
        error =>
          raise match error {
            OperationFailed(action~, status~, detail~) =>
              RuntimeOperationFailed(action~, status~, detail~)
            other => UnexpectedTaskFailure(detail=other.message())
          }
      },
    )
  }
  self.windows.push(running)
  self.has_created_window = true
  // A new window starts a new last-window policy period: closing it again may
  // request quit even when an earlier automatic request was prevented.
  self.close_coordinator.last_window_quit_handled = false
  // Report creation the way Electron does: the web contents exists before the
  // window joins the application's window list, and planned views follow it.
  self.emit_web_contents_created(self.browser_handle(running))
  self.emit_window_created(running)
  for view in running.views {
    self.emit_web_contents_created(
      self.view_handle(running, view).web_contents(),
    )
  }
  @xlog.info(category="proton.window") <?
    { "message": "window created", "window": running.id }
  running
}

///|
async fn RuntimeSession::activate_window(
  self : RuntimeSession,
  running : RunningWindow,
) -> Unit {
  if running.lifetime.ready {
    running.lifetime.wait_until_ready()
    return
  }
  let window_events = WindowEventEmitter(
    typed_event_sender(running.window, None),
  )
  let manager = self.window_manager()
  let handle = self.window_handle(running)
  running.lifetime.task = Some(
    self.window_tasks.spawn(
      () => {
        defer {
          running.lifetime.task = None
        }
        run_window_lifecycle_scope(
          running,
          handle,
          manager,
          window_events,
          self.config.window_lifecycle_hooks,
          self.lifecycle_failures,
          self.environment.locale_preferences,
        )
      },
      no_wait=true,
    ),
  )
  running.lifetime.wait_until_ready()
  if !running.is_active() {
    return
  }
  running.window.show() catch {
    error => raise native_run_error("show window " + running.id, error)
  }
  running.state = WindowOpen
}

///|
async fn RuntimeSession::request_open_window(
  self : RuntimeSession,
  id : String,
) -> WindowHandle {
  if self.is_quitting() {
    raise ApplicationQuitting
  }
  let completion = WindowOpenCompletion()
  self.window_commands.push(Open(id, completion))
  self.wakeup.signal.notify()
  defer self.wakeup.signal.notify()
  completion.wait()
}

///|
fn WindowOpenCompletion::WindowOpenCompletion() -> WindowOpenCompletion {
  WindowOpenCompletion::{
    state: WindowOpenPending,
    changed: @async.CondVar::Cond(),
  }
}

///|
fn WindowOpenCompletion::succeed(
  self : WindowOpenCompletion,
  handle : WindowHandle,
) -> Unit {
  if self.state is WindowOpenPending {
    self.state = WindowOpenSucceeded(handle)
    self.changed.broadcast()
  }
}

///|
fn WindowOpenCompletion::fail(
  self : WindowOpenCompletion,
  error : WindowSessionError,
) -> Unit {
  if self.state is WindowOpenPending {
    self.state = WindowOpenFailed(error)
    self.changed.broadcast()
  }
}

///|
async fn WindowOpenCompletion::wait(
  self : WindowOpenCompletion,
) -> WindowHandle {
  // Cancellation before success belongs to the opening operation, not just
  // its waiter. Preserve cancellation of the calling task.
  defer self.fail(Cancelled)
  while self.state is WindowOpenPending {
    self.changed.wait()
  }
  match self.state {
    WindowOpenSucceeded(handle) => handle
    WindowOpenFailed(error) => raise error
    WindowOpenPending => abort("unreachable pending window completion")
  }
}

///|
fn RuntimeSession::process_window_commands(self : RuntimeSession) -> Bool {
  guard self.window_commands.length() > 0 else { return false }
  let commands = self.window_commands.copy()
  self.window_commands.clear()
  for command in commands {
    let Open(id, completion) = command
    guard completion.state is WindowOpenPending else { continue }
    if self.is_quitting() {
      completion.fail(ApplicationQuitting)
      continue
    }
    let definition = match self.find_definition(id) {
      Some(definition) => definition
      None => {
        completion.fail(UnknownWindow(id~))
        continue
      }
    }
    if self.find_active_window(id) is Some(_) {
      completion.fail(AlreadyOpen(id~))
      continue
    }
    let running = self.create_window(definition) catch {
      error => {
        completion.fail(StartupFailed(id~, error~))
        continue
      }
    }
    let timeout = self.window_tasks.spawn(
      () => {
        defer self.wakeup.signal.notify()
        @async.sleep(self.config.bridge_startup_timeout_ms)
      },
      no_wait=true,
      allow_failure=true,
    )
    self.pending_window_opens.push(PendingWindowOpen::{
      id,
      running,
      completion,
      activation: None,
      timeout,
    })
  }
  true
}

///|
fn RuntimeSession::advance_window_opens(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  let remaining : Array[PendingWindowOpen] = []
  let mut did_work = false
  for pending in self.pending_window_opens {
    if pending.completion.state is WindowOpenFailed(_) {
      self.discard_window_open(pending) catch {
        error => raise CleanupFailed(primary=None, failures=[error])
      }
      did_work = true
      continue
    }
    let timed_out = pending.timeout.try_wait() catch { _ => Some(()) }
    if timed_out is Some(_) {
      did_work = true
      let state = pending.running.window.bridge_lifecycle_state() catch {
        error =>
          raise native_run_error("read timed-out bridge startup state", error)
      }
      let error = match state {
        Some(state) =>
          BridgeStartupError(
            BridgeDiagnostic::from_native(
              bridge_startup_timeout_diagnostic(
                state,
                self.config.bridge_startup_timeout_ms,
              ),
            ),
          )
        None => EntryLoadError(ClosedDuringStartup)
      }
      self.fail_window_open(pending, error)
      continue
    }
    match pending.activation {
      Some(task) => {
        let completed = task.try_wait() catch {
          error => {
            did_work = true
            self.fail_window_open(pending, normalize_async_run_error(error))
            None
          }
        }
        if pending.completion.state is WindowOpenFailed(_) {
          continue
        }
        match completed {
          Some(_) => {
            did_work = true
            pending.timeout.cancel()
            if !pending.running.is_active() {
              pending.completion.fail(Cancelled)
            } else {
              pending.completion.succeed(self.window_handle(pending.running))
            }
          }
          None => remaining.push(pending)
        }
      }
      None => {
        let ready = if self.monitor_bridge {
          refresh_window_bridge_startup_state(pending.running) catch {
            error => {
              did_work = true
              self.fail_window_open(pending, error)
              false
            }
          }
        } else {
          true
        }
        if pending.completion.state is WindowOpenFailed(_) {
          continue
        }
        if ready {
          did_work = true
          pending.activation = Some(
            self.window_tasks.spawn(
              () => {
                defer self.wakeup.signal.notify()
                self.activate_window(pending.running)
              },
              no_wait=true,
              allow_failure=true,
            ),
          )
        }
        remaining.push(pending)
      }
    }
  }
  self.pending_window_opens.clear()
  for pending in remaining {
    self.pending_window_opens.push(pending)
  }
  did_work
}

///|
fn RuntimeSession::discard_window_open(
  self : RuntimeSession,
  pending : PendingWindowOpen,
) -> Unit raise AppCleanupError {
  pending.timeout.cancel()
  match pending.activation {
    Some(task) => task.cancel()
    None => ()
  }
  match pending.running.lifetime.task {
    Some(task) => task.cancel()
    None => ()
  }
  self.retire_window(pending.running)
}

///|
fn RuntimeSession::fail_window_open(
  self : RuntimeSession,
  pending : PendingWindowOpen,
  error : AppRunError,
) -> Unit raise AppRunError {
  pending.completion.fail(StartupFailed(id=pending.id, error~))
  self.discard_window_open(pending) catch {
    cleanup =>
      raise CleanupFailed(primary=Some(error.message()), failures=[cleanup])
  }
}

///|
/// Opens one declared window that is not currently active.
/// Business failures raise `WindowSessionError`; task cancellation propagates
/// unchanged to the owning async task group. Before activation succeeds,
/// cancellation discards queued work or closes the instance created by this
/// operation. Once activation success is committed, the application owns the
/// window; later caller cancellation does not close it.
pub async fn WindowManager::open(
  self : WindowManager,
  id : String,
) -> WindowHandle {
  (self.open_window)(id)
}

///|
/// Returns the active instance for a declared window id.
/// This includes starting windows. Finding a window does not wait for native
/// browser initialization, page loading, or command bridge readiness.
/// Browser operations may still fail while the native browser is starting.
pub fn WindowManager::find(self : WindowManager, id : String) -> WindowHandle? {
  (self.find_window)(id)
}

///|
/// Returns the declarative id of this window.
pub fn WindowHandle::id(self : WindowHandle) -> String {
  self.id
}

///|
/// Returns the declarative id of the window owning this web contents.

///|
pub fn WindowHandle::show(self : WindowHandle) -> Unit raise WindowSessionError {
  self.with_window("show", window => window.show())
}

///|
/// Shows the window without activating it.
pub fn WindowHandle::show_inactive(
  self : WindowHandle,
) -> Unit raise WindowSessionError {
  self.with_window("show inactive", window => window.show_inactive())
}

///|
pub fn WindowHandle::is_visible(
  self : WindowHandle,
) -> Bool raise WindowSessionError {
  self.state().visible
}

///|
pub fn WindowHandle::is_focused(
  self : WindowHandle,
) -> Bool raise WindowSessionError {
  self.state().focused
}

///|
pub fn WindowHandle::hide(self : WindowHandle) -> Unit raise WindowSessionError {
  self.with_window("hide", window => window.hide())
}

///|
pub fn WindowHandle::close(
  self : WindowHandle,
) -> Unit raise WindowSessionError {
  self.session.close_window(self.id, self.native_id)
}

///|
pub fn WindowHandle::focus(
  self : WindowHandle,
) -> Unit raise WindowSessionError {
  self.with_window("focus", window => window.focus())
}

///|
pub fn WindowHandle::set_title(
  self : WindowHandle,
  title : String,
) -> Unit raise WindowSessionError {
  self.with_window("set title", window => window.set_title(title))
}

///|
/// Sets the native window icon from an image file path.
pub fn WindowHandle::set_icon(
  self : WindowHandle,
  path : String,
) -> Unit raise WindowSessionError {
  self.with_window("set icon", window => window.set_icon(path))
}

///|
/// Establishes or clears this window's native parent relationship.
pub fn WindowHandle::set_parent(
  self : WindowHandle,
  parent : WindowHandle?,
  modal? : Bool = false,
) -> Unit raise WindowSessionError {
  let parent_native_id = parent.map(parent => parent.native_id)
  self.session.set_window_parent(
    self.id,
    self.native_id,
    parent_native_id,
    modal,
  )
}

///|
pub fn WindowHandle::set_size(
  self : WindowHandle,
  width : Int,
  height : Int,
) -> Unit raise WindowSessionError {
  self.with_window("set size", window => window.set_size(width, height))
}

///|
/// Sets the renderer content area in logical pixels.
pub fn WindowHandle::set_content_size(
  self : WindowHandle,
  width : Int,
  height : Int,
) -> Unit raise WindowSessionError {
  self.with_window("set content size", window => {
    window.set_content_size(width, height)
  })
}

///|
/// Returns the renderer content area in logical pixels.
pub fn WindowHandle::content_size(
  self : WindowHandle,
) -> (Int, Int) raise WindowSessionError {
  self.session.read_window_content_size(self.id, self.native_id)
}

///|
/// Returns `(x, y, width, height)` in logical screen pixels, matching
/// Electron's `getBounds` coordinate order.
pub fn WindowHandle::bounds(
  self : WindowHandle,
) -> (Int, Int, Int, Int) raise WindowSessionError {
  let state = self.state()
  (state.x, state.y, state.width, state.height)
}

///|
/// Returns the window's `(x, y)` position in logical screen pixels.
pub fn WindowHandle::position(
  self : WindowHandle,
) -> (Int, Int) raise WindowSessionError {
  let state = self.state()
  (state.x, state.y)
}

///|
/// Returns the window's `(width, height)` frame size in logical pixels.
pub fn WindowHandle::size(
  self : WindowHandle,
) -> (Int, Int) raise WindowSessionError {
  let state = self.state()
  (state.width, state.height)
}

///|
/// Sets `(x, y, width, height)` in logical screen pixels, matching Electron's
/// `setBounds` coordinate order.
pub fn WindowHandle::set_bounds(
  self : WindowHandle,
  x~ : Int,
  y~ : Int,
  width~ : Int,
  height~ : Int,
) -> Unit raise WindowSessionError {
  self.set_position(x, y)
  self.set_size(width, height)
}

///|
pub fn WindowHandle::minimize(
  self : WindowHandle,
) -> Unit raise WindowSessionError {
  self.with_window("minimize", window => window.minimize())
}

///|
pub fn WindowHandle::maximize(
  self : WindowHandle,
) -> Unit raise WindowSessionError {
  self.with_window("maximize", window => window.maximize())
}

///|
pub fn WindowHandle::restore(
  self : WindowHandle,
) -> Unit raise WindowSessionError {
  self.with_window("restore", window => window.restore())
}

///|
/// Reports whether the window is currently minimized.
pub fn WindowHandle::is_minimized(
  self : WindowHandle,
) -> Bool raise WindowSessionError {
  self.state().minimized
}

///|
/// Reports whether the window is currently maximized.
pub fn WindowHandle::is_maximized(
  self : WindowHandle,
) -> Bool raise WindowSessionError {
  self.state().maximized
}

///|
/// Reports whether the window is currently fullscreen.
pub fn WindowHandle::is_fullscreen(
  self : WindowHandle,
) -> Bool raise WindowSessionError {
  self.state().fullscreen
}

///|
/// Reports whether the window is currently kept above other windows.
pub fn WindowHandle::is_always_on_top(
  self : WindowHandle,
) -> Bool raise WindowSessionError {
  self.state().always_on_top
}

///|
pub fn WindowHandle::set_fullscreen(
  self : WindowHandle,
  fullscreen : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set fullscreen", window => window.set_fullscreen(fullscreen))
}

///|
/// Enters or leaves kiosk mode.
///
/// Kiosk uses the full display and hides system chrome where the platform
/// supports it. Call with `false` to provide a programmatic exit path.
pub fn WindowHandle::set_kiosk(
  self : WindowHandle,
  kiosk : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set kiosk", window => window.set_kiosk(kiosk))
}

///|
pub fn WindowHandle::set_position(
  self : WindowHandle,
  x : Int,
  y : Int,
) -> Unit raise WindowSessionError {
  self.with_window("set position", window => window.set_position(x, y))
}

///|
/// Centers the window in the work area of the monitor containing it.
///
/// The current native frame size is preserved. Work-area coordinates exclude
/// taskbars, docks, and other reserved desktop regions, and use Proton's
/// top-left coordinate convention on every platform.
pub fn WindowHandle::center(
  self : WindowHandle,
) -> Unit raise WindowSessionError {
  let (x, y) = self.state().center_position()
  self.set_position(x, y)
}

///|
fn WindowState::center_position(self : WindowState) -> (Int, Int) {
  let monitor = self.monitor
  let (width, height) = @native.window_size_in_screen_coordinates(
    self.width,
    self.height,
    monitor.scale_factor_percent,
  )
  (
    monitor.work_x + (monitor.work_width - width) / 2,
    monitor.work_y + (monitor.work_height - height) / 2,
  )
}

///|
pub fn WindowHandle::set_always_on_top(
  self : WindowHandle,
  always_on_top : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set always on top", window => {
    window.set_always_on_top(always_on_top)
  })
}

///|
/// Sets whether the user can manually resize this window.
///
/// This changes the live native window on macOS, Windows, and Linux. Existing
/// minimum or maximum size hints remain in effect. Headless runtimes raise
/// `WindowSessionError`.
pub fn WindowHandle::set_resizable(
  self : WindowHandle,
  resizable : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set resizable", window => window.set_resizable(resizable))
}

///|
/// Sets the minimum live native window size.
///
/// Both dimensions must be positive, or both must be zero to clear the
/// constraint. Existing maximum size and resizable state remain unchanged.
/// Headless runtimes raise `WindowSessionError`.
pub fn WindowHandle::set_minimum_size(
  self : WindowHandle,
  width : Int,
  height : Int,
) -> Unit raise WindowSessionError {
  self.with_window("set minimum size", window => {
    window.set_minimum_size(width, height)
  })
}

///|
/// Sets the maximum live native window size.
///
/// Both dimensions must be positive, or both must be zero to clear the
/// constraint. Existing minimum size and resizable state remain unchanged.
/// Headless runtimes raise `WindowSessionError`.
pub fn WindowHandle::set_maximum_size(
  self : WindowHandle,
  width : Int,
  height : Int,
) -> Unit raise WindowSessionError {
  self.with_window("set maximum size", window => {
    window.set_maximum_size(width, height)
  })
}

///|
/// Sets the live native window aspect ratio used while the user resizes it.
/// Pass `0.0` to clear the constraint. Programmatic `set_size` calls are not
/// constrained by the ratio, matching Electron's `setAspectRatio` behavior.
/// Headless runtimes raise `WindowSessionError`.
pub fn WindowHandle::set_aspect_ratio(
  self : WindowHandle,
  aspect_ratio : Double,
) -> Unit raise WindowSessionError {
  self.with_window("set aspect ratio", window => {
    window.set_aspect_ratio(aspect_ratio)
  })
}

///|
/// Sets whether the user can move this live native window.
///
/// macOS and Windows prevent manual frame movement when `movable` is false;
/// programmatic `set_position` and `center` calls remain available. Linux
/// follows Electron and treats this as a no-op. Headless runtimes raise
/// `WindowSessionError` because they have no native frame.
pub fn WindowHandle::set_movable(
  self : WindowHandle,
  movable : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set movable", window => window.set_movable(movable))
}

///|
/// Sets the live native window opacity.
///
/// Values are clamped to the Electron-compatible `0.0..1.0` range, where
/// `0.0` is fully transparent and `1.0` is fully opaque. Headless runtimes
/// raise `WindowSessionError` because they have no native frame.
pub fn WindowHandle::set_opacity(
  self : WindowHandle,
  opacity : Double,
) -> Unit raise WindowSessionError {
  self.with_window("set opacity", window => window.set_opacity(opacity))
}

///|
/// Sets whether this live native window is omitted from the taskbar or dock.
///
/// Windows removes or restores the taskbar tab. macOS and Linux follow
/// Electron and treat this as a no-op. Headless runtimes raise
/// `WindowSessionError` because they have no native window shell.
pub fn WindowHandle::set_skip_taskbar(
  self : WindowHandle,
  skip : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set taskbar visibility", window => {
    window.set_skip_taskbar(skip)
  })
}

///|
/// Sets whether other applications should be prevented from capturing this
/// live native window.
///
/// macOS applies `NSWindowSharingNone`, although ScreenCaptureKit-based apps
/// on recent macOS releases may still capture the window. Windows uses display
/// affinity to exclude the window from capture. Linux follows Electron and
/// treats this as a no-op. Headless runtimes raise `WindowSessionError`.
pub fn WindowHandle::set_content_protection(
  self : WindowHandle,
  enabled : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set content protection", window => {
    window.set_content_protection(enabled)
  })
}

///|
/// Sets whether the user can manually minimize this live native window.
/// macOS and Windows update the native minimize control; Linux follows
/// Electron and treats this as a successful no-op. Headless runtimes raise
/// `WindowSessionError`.
pub fn WindowHandle::set_minimizable(
  self : WindowHandle,
  minimizable : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set minimizable", window => {
    window.set_minimizable(minimizable)
  })
}

///|
/// Sets whether the user can manually maximize this live native window.
/// macOS and Windows update the native maximize/zoom control; Linux follows
/// Electron and treats this as a successful no-op. Headless runtimes raise
/// `WindowSessionError`.
pub fn WindowHandle::set_maximizable(
  self : WindowHandle,
  maximizable : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set maximizable", window => {
    window.set_maximizable(maximizable)
  })
}

///|
/// Sets whether the user can manually close this live native window.
///
/// macOS and Windows update the native close control; programmatic `close`
/// calls remain available. Linux follows Electron and treats this as a
/// successful no-op. Headless runtimes raise `WindowSessionError`.
pub fn WindowHandle::set_closable(
  self : WindowHandle,
  closable : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set closable", window => window.set_closable(closable))
}

///|
/// Sets visibility of the standard close, minimize, and maximize buttons.
/// On macOS this updates the native traffic-light controls. Other platforms
/// apply the equivalent live capability controls where available.
pub fn WindowHandle::set_window_button_visibility(
  self : WindowHandle,
  visible : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set window button visibility", window => {
    window.set_button_visibility(visible)
  })
}

///|
/// Sets whether this live native window can receive focus.
///
/// macOS and Windows update the native window behavior. On macOS, disabling
/// focus does not remove focus from a window that is already focused, matching
/// Electron. Linux follows Electron and treats this as a successful no-op.
/// Headless runtimes raise `WindowSessionError`.
pub fn WindowHandle::set_focusable(
  self : WindowHandle,
  focusable : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set focusable", window => window.set_focusable(focusable))
}

///|
/// Sets whether this live native window can enter fullscreen mode.
///
/// When disabled, attempts to enter fullscreen are ignored. An already
/// fullscreen window can still exit fullscreen.
pub fn WindowHandle::set_fullscreenable(
  self : WindowHandle,
  fullscreenable : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set fullscreenable", window => {
    window.set_fullscreenable(fullscreenable)
  })
}

///|
/// Sets whether this live native window draws a frame shadow.
///
/// macOS applies this directly to the native window. Linux and Windows accept
/// the setting as a successful no-op when the platform frame owns the shadow.
/// Headless runtimes raise `WindowSessionError`.
pub fn WindowHandle::set_has_shadow(
  self : WindowHandle,
  has_shadow : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set window shadow", window => {
    window.set_has_shadow(has_shadow)
  })
}

///|
/// Sets whether this live native window ignores mouse events.
///
/// When `ignore` is true, mouse input passes through to the window below while
/// keyboard input remains available to the focused window. `forward` requests
/// mouse-move forwarding to Chromium where the platform supports it. Forwarding
/// is disabled automatically when `ignore` is false.
pub fn WindowHandle::set_ignore_mouse_events(
  self : WindowHandle,
  ignore : Bool,
  forward : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set ignore mouse events", window => {
    window.set_ignore_mouse_events(ignore, forward)
  })
}

///|
/// Sets the live native window background color.
///
/// Accepts `#RRGGBB` or `#AARRGGBB`, matching Proton view configuration.
pub fn WindowHandle::set_background_color(
  self : WindowHandle,
  color : String,
) -> Unit raise WindowSessionError {
  self.with_window("set background color", window => {
    window.set_background_color(color)
  })
}

///|
/// Sets the native window chrome theme.
///
/// `System` follows platform appearance changes. Explicit `Light` and `Dark`
/// remain stable until changed again and raise `WindowSessionError` on
/// platforms without per-window native theme support.
pub fn WindowHandle::set_theme(
  self : WindowHandle,
  theme : WindowThemePreference,
) -> Unit raise WindowSessionError {
  self.with_window("set theme", window => {
    window.set_theme(
      match theme {
        WindowThemePreference::System => @native.WindowThemePreference::System
        WindowThemePreference::Light => @native.WindowThemePreference::Light
        WindowThemePreference::Dark => @native.WindowThemePreference::Dark
      },
    )
  })
}

///|
/// Sets whether the live window appears on every workspace.
///
/// This maps to Spaces on macOS and sticky windows on Linux. It is a
/// successful no-op on Windows, matching Electron.
pub fn WindowHandle::set_visible_on_all_workspaces(
  self : WindowHandle,
  visible : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set workspace visibility", window => {
    window.set_visible_on_all_workspaces(visible)
  })
}

///|
/// Enables or disables user interaction with the live native window.
pub fn WindowHandle::set_enabled(
  self : WindowHandle,
  enabled : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("set enabled", window => window.set_enabled(enabled))
}

///|
/// Replaces the native menu for the application runtime containing this window.
/// Passing `None` clears the menu.
pub fn WindowHandle::set_menu(
  self : WindowHandle,
  menu : MenuBar?,
) -> Unit raise WindowSessionError {
  try {
    match menu {
      Some(menu) => self.session.runtime.set_menu(menu.to_native())
      None => self.session.runtime.set_menu(@native.MenuBar(menus=[]))
    }
  } catch {
    error =>
      raise window_operation_failed("set menu in window " + self.id, error)
  }
}

///|
/// Returns the main browser zoom percentage.
pub fn WindowHandle::zoom_percent(
  self : WindowHandle,
) -> Int raise WindowSessionError {
  self.state().zoom_percent
}

///|
/// Sets the platform progress indicator using Electron-compatible values.
///
/// Pass a negative value to clear the indicator, a value from `0.0` through
/// `1.0` for determinate progress, or a value above `1.0` for indeterminate
/// progress. `mode` mirrors Electron's `mode` option and selects an explicit
/// state instead; only Windows renders it.
///
/// macOS displays this in the Dock as one application-level indicator, so the
/// most recent window call wins and any negative value clears it. Windows
/// displays it on the taskbar button, where the error and paused states keep
/// showing the value. Linux has no implementation and raises
/// `WindowSessionError`.
pub fn WindowHandle::set_progress_bar(
  self : WindowHandle,
  progress : Double,
  mode? : ProgressBarMode = ProgressBarMode::Automatic,
) -> Unit raise WindowSessionError {
  self.with_window("set progress bar", window => {
    window.set_progress_bar(progress, mode.to_native())
  })
}

///|
/// Sets or clears the taskbar overlay icon shown in the bottom right of the
/// window's taskbar button.
///
/// Pass `None` to clear the overlay. `description` is read by accessibility
/// screen readers. Windows scales the image to the 16x16 overlay area, keeps
/// the aspect ratio, and clips it to a circle; other platforms accept the call
/// and do nothing, matching Electron.
pub fn WindowHandle::set_overlay_icon(
  self : WindowHandle,
  overlay : NativeImage?,
  description : String,
) -> Unit raise WindowSessionError {
  self.with_window("set overlay icon", window => {
    window.set_overlay_icon(overlay.map(image => image.image), description)
  })
}

///|
/// Sets the tooltip shown when the pointer rests over the window's taskbar
/// thumbnail. Only Windows displays it; other platforms accept the call and do
/// nothing, matching Electron.
pub fn WindowHandle::set_thumbnail_tooltip(
  self : WindowHandle,
  tooltip : String,
) -> Unit raise WindowSessionError {
  self.with_window("set thumbnail tooltip", window => {
    window.set_thumbnail_tooltip(tooltip)
  })
}

///|
/// Replaces the taskbar thumbnail toolbar, the row of buttons shown under the
/// window's taskbar thumbnail. Up to seven buttons are supported, and an empty
/// array clears the buttons that were added before.
///
/// The result reports whether the platform showed the buttons. Windows returns
/// the taskbar result; macOS and Linux return `false` because Electron marks
/// the thumbnail toolbar as Windows only. Invalid input — more than seven
/// buttons, an empty `id`, or a released image — raises
/// `WindowSessionError`.
///
/// The button slots are claimed by the first successful call, which is a
/// Windows limitation Electron documents as well: a later call can replace or
/// hide buttons, but it cannot remove the toolbar.
pub fn WindowHandle::set_thumbar_buttons(
  self : WindowHandle,
  buttons : Array[ThumbarButton],
) -> Bool raise WindowSessionError {
  self.session.set_window_thumbar_buttons(
    self.id,
    self.native_id,
    buttons.map(button => button.to_native()),
  )
}

///|
/// Starts or stops flashing the window to attract the user's attention.
///
/// On macOS, `true` continuously bounces the application Dock icon until the
/// application becomes active or `flash_frame(false)` cancels the request. On
/// Windows it flashes the taskbar button until the window becomes active, and
/// on Linux it sets the desktop window urgency hint. Headless runtimes raise
/// `WindowSessionError`.
pub fn WindowHandle::flash_frame(
  self : WindowHandle,
  flash : Bool,
) -> Unit raise WindowSessionError {
  self.with_window("flash frame", window => window.flash_frame(flash))
}

///|
pub fn WindowHandle::state(
  self : WindowHandle,
) -> WindowState raise WindowSessionError {
  self.session.read_window_state(self.id, self.native_id)
}

///|
fn WindowHandle::popup_menu(
  self : WindowHandle,
  menu : Menu,
  x : Int,
  y : Int,
) -> Unit raise WindowSessionError {
  self.with_window("popup menu in", window => {
    window.popup_menu(@native.MenuBar(menus=[menu.to_native()]), x, y)
  })
}

///|
/// Returns the webpage hosted in this window.
pub fn WindowHandle::web_contents(self : WindowHandle) -> WebContentsHandle {
  {
    session: self.session,
    id: self.id,
    native_id: self.native_id,
    target: PrimaryPage,
  }
}

///|
/// Adds a web contents view to this window, following the Electron
/// `WebContentsView` model: the view renders its own page above the window's
/// main browser content at explicit bounds. `id` is unique within the window
/// and lets the session reject stale handles.
pub fn WindowHandle::add_view(
  self : WindowHandle,
  id : String,
  config : ViewConfig,
) -> ViewHandle raise WindowSessionError {
  self.session.add_window_view(self.id, self.native_id, id, config.to_native())
}

///|
/// Removes and destroys a web contents view previously added with `add_view`.
pub fn WindowHandle::remove_view(
  self : WindowHandle,
  id : String,
) -> Unit raise WindowSessionError {
  self.session.remove_window_view(self.id, self.native_id, id)
}

///|
/// Lists the live web contents views of this window.
pub fn WindowHandle::views(self : WindowHandle) -> Array[ViewHandle] {
  self.session.list_window_views(self.id, self.native_id)
}

///|
/// Returns the live view with the given declarative id, if one exists.
pub fn WindowHandle::view(self : WindowHandle, id : String) -> ViewHandle? {
  self.session.find_window_view(self.id, self.native_id, id)
}

///|
/// Returns the declarative id of this view.
pub fn ViewHandle::id(self : ViewHandle) -> String {
  self.id
}

///|
/// Returns the declarative id of the window that hosts this view.
pub fn ViewHandle::window_id(self : ViewHandle) -> String {
  self.window_id
}

///|
/// Moves and resizes the view. `x`/`y` use a top-left origin in the owning
/// window's content coordinate space, matching Electron's `setBounds`.
pub fn ViewHandle::set_bounds(
  self : ViewHandle,
  x~ : Int,
  y~ : Int,
  width~ : Int,
  height~ : Int,
) -> Unit raise WindowSessionError {
  self.with_view("set bounds of", view => {
    view.set_bounds(x~, y~, width~, height~)
  })
}

///|
pub fn ViewHandle::set_visible(
  self : ViewHandle,
  visible : Bool,
) -> Unit raise WindowSessionError {
  self.with_view("set visibility of", view => view.set_visible(visible))
}

///|
/// Stacks the view relative to the window's other views; higher `z_order`
/// renders above lower values.
pub fn ViewHandle::set_z_order(
  self : ViewHandle,
  z_order : Int,
) -> Unit raise WindowSessionError {
  self.with_view("set z-order of", view => view.set_z_order(z_order))
}

///|
/// Reads the current view state from the native runtime.
pub fn ViewHandle::state(
  self : ViewHandle,
) -> ViewState raise WindowSessionError {
  let running = self.session.resolve_view(
    self.window_id,
    self.window_native_id,
    self.id,
    self.native_id,
  )
  ViewState::from_native(running.view.state()) catch {
    error =>
      raise window_operation_failed(
        "read view " + self.id + " state in window " + self.window_id,
        error,
      )
  }
}

///|
/// Removes and destroys the view, the Electron `removeChildView` equivalent.
/// The view immediately becomes unavailable for operations and lookup. Its
/// native close notification is delivered later through `App::on_web_contents_event`
/// if the parent window remains alive. The declarative id may be reused.
pub fn ViewHandle::close(self : ViewHandle) -> Unit raise WindowSessionError {
  ignore(
    self.session.resolve_view(
      self.window_id,
      self.window_native_id,
      self.id,
      self.native_id,
    ),
  )
  self.session.remove_window_view(
    self.window_id,
    self.window_native_id,
    self.id,
  )
}

///|
fn[T] WebContentsHandle::with_target(
  self : WebContentsHandle,
  action : String,
  operation : (ResolvedWebContents) -> T raise @native.NativeError,
) -> T raise WindowSessionError {
  let (target, description) = match self.target {
    PrimaryPage => {
      let window = self.session.resolve_window(self.id, self.native_id)
      (ResolvedWebContents::PrimaryPage(window.window), "window " + self.id)
    }
    ChildView(id, native_id) => {
      let view = self.session.resolve_view(
        self.id,
        self.native_id,
        id,
        native_id,
      )
      (
        ResolvedWebContents::ChildView(view.view),
        "view " + id + " in window " + self.id,
      )
    }
  }
  operation(target) catch {
    error => raise window_operation_failed(action + " " + description, error)
  }
}

///|
fn WebContentsHandle::browser_command(
  self : WebContentsHandle,
  command : String,
  download_id : Int?,
) -> Unit raise WindowSessionError {
  self.with_target(command + " in", target => {
    match target {
      PrimaryPage(window) => window.browser_command(command, download_id?)
      ChildView(view) => view.browser_command(command, download_id?)
    }
  })
}

///|
fn WebContentsHandle::navigation_state(
  self : WebContentsHandle,
) -> (Bool, Bool) raise WindowSessionError {
  self.with_target("read navigation state of", target => {
    match target {
      PrimaryPage(window) => window.navigation_state()
      ChildView(view) => view.navigation_state()
    }
  })
}

///|
pub fn WebContentsHandle::window_id(self : WebContentsHandle) -> String {
  self.id
}

///|
pub fn WebContentsHandle::load_url(
  self : WebContentsHandle,
  url : String,
) -> Unit raise WindowSessionError {
  self.with_target("load URL in", target => {
    match target {
      PrimaryPage(window) => window.load_url(url)
      ChildView(view) => view.load_url(url)
    }
  })
}

///|
pub fn WebContentsHandle::load_html(
  self : WebContentsHandle,
  html : String,
  base_url : String,
) -> Unit raise WindowSessionError {
  match self.target {
    PrimaryPage =>
      self.session.load_window_html(self.id, self.native_id, html, base_url)
    ChildView(id, native_id) =>
      self.session.load_view_html(
        self.id,
        self.native_id,
        id,
        native_id,
        html,
        base_url,
      )
  }
}

///|
pub fn WebContentsHandle::eval(
  self : WebContentsHandle,
  script : String,
) -> Unit raise WindowSessionError {
  self.with_target("evaluate script in", target => {
    match target {
      PrimaryPage(window) => window.eval(script)
      ChildView(view) => view.eval(script)
    }
  })
}

///|
/// Starts or advances a page search and returns its request id. Set
/// `find_next=true` to begin a new search session, matching Electron's
/// `findInPage` option; leave it false to advance the current session.
pub fn WebContentsHandle::find_in_page(
  self : WebContentsHandle,
  text : String,
  forward? : Bool = true,
  match_case? : Bool = false,
  find_next? : Bool = false,
) -> Int raise WindowSessionError {
  self.with_target("find in", target => {
    match target {
      PrimaryPage(window) =>
        window.find_in_page(text, forward, match_case, find_next)
      ChildView(view) => view.find_in_page(text, forward, match_case, find_next)
    }
  })
}

///|
/// Stops the active page search. Set `clear_selection=false` to preserve the
/// current match highlight.
pub fn WebContentsHandle::stop_find_in_page(
  self : WebContentsHandle,
  clear_selection? : Bool = true,
) -> Unit raise WindowSessionError {
  self.with_target("stop find in", target => {
    match target {
      PrimaryPage(window) => window.stop_find_in_page(clear_selection)
      ChildView(view) => view.stop_find_in_page(clear_selection)
    }
  })
}

///|
/// Starts downloading `url` without navigating the page. The request uses the
/// app's download approval and progress handlers. CEF does not support
/// Electron's optional custom request headers for this operation.
pub fn WebContentsHandle::download_url(
  self : WebContentsHandle,
  url : String,
) -> Unit raise WindowSessionError {
  self.with_target("download URL in", target => {
    match target {
      PrimaryPage(window) => window.download_url(url)
      ChildView(view) => view.download_url(url)
    }
  })
}

///|
/// Opens the platform print flow for the main browser contents.
pub fn WebContentsHandle::print(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.with_target("print", target => {
    match target {
      PrimaryPage(window) => window.print()
      ChildView(view) => view.print()
    }
  })
}

///|
/// Prints this page to `path`, returning only after the PDF is written.
/// Start/completion failures and page closure raise `WindowSessionError`.
/// Task cancellation stops waiting, but CEF may still finish writing the file.
pub async fn WebContentsHandle::print_to_pdf(
  self : WebContentsHandle,
  path : String,
  options? : PdfPrintOptions = PdfPrintOptions(),
) -> Unit {
  let request_id = self.with_target("print to PDF in", target => {
    match target {
      PrimaryPage(window) => window.print_to_pdf(path, options.to_native())
      ChildView(view) => view.print_to_pdf(path, options.to_native())
    }
  })
  let view_id = match self.target {
    PrimaryPage => None
    ChildView(_, native_id) => Some(native_id)
  }
  self.session.event_pump.pdf_completions.wait(
    self.native_id,
    view_id,
    request_id,
    path,
  )
}

///|
pub fn WebContentsHandle::back(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.browser_command("back", None)
}

///|
pub fn WebContentsHandle::forward(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.browser_command("forward", None)
}

///|
/// Sets the main browser zoom from 25% through 500%.
pub fn WebContentsHandle::set_zoom_percent(
  self : WebContentsHandle,
  zoom_percent : Int,
) -> Unit raise WindowSessionError {
  self.with_target("set zoom of", target => {
    match target {
      PrimaryPage(window) => window.set_zoom_percent(zoom_percent)
      ChildView(view) => view.set_zoom_percent(zoom_percent)
    }
  })
}

///|
/// Returns the main browser zoom percentage.
pub fn WebContentsHandle::zoom_percent(
  self : WebContentsHandle,
) -> Int raise WindowSessionError {
  self.with_target("read zoom of", target => {
    match target {
      PrimaryPage(window) => window.state().zoom_percent
      ChildView(view) => view.zoom_percent()
    }
  })
}

///|
/// Mutes or unmutes audio produced by the main browser page.
pub fn WebContentsHandle::set_audio_muted(
  self : WebContentsHandle,
  muted : Bool,
) -> Unit raise WindowSessionError {
  self.with_target("set audio mute of", target => {
    match target {
      PrimaryPage(window) => window.set_audio_muted(muted)
      ChildView(view) => view.set_audio_muted(muted)
    }
  })
}

///|
/// Returns whether audio produced by the main browser page is muted.
pub fn WebContentsHandle::is_audio_muted(
  self : WebContentsHandle,
) -> Bool raise WindowSessionError {
  self.with_target("read audio mute of", target => {
    match target {
      PrimaryPage(window) => window.is_audio_muted()
      ChildView(view) => view.is_audio_muted()
    }
  })
}

///|
/// Returns whether the main browser can navigate to a previous history entry.
pub fn WebContentsHandle::can_go_back(
  self : WebContentsHandle,
) -> Bool raise WindowSessionError {
  self.navigation_state().0
}

///|
/// Returns whether the main browser can navigate to a later history entry.
pub fn WebContentsHandle::can_go_forward(
  self : WebContentsHandle,
) -> Bool raise WindowSessionError {
  self.navigation_state().1
}

///|
/// Reads the current main browser page state.
/// Requires an initialized native browser; finding its window does not ensure
/// this. A query made before initialization raises `WindowSessionError`.
/// A returned state does not by itself establish successful page loading or
/// command bridge readiness.
pub fn WebContentsHandle::state(
  self : WebContentsHandle,
) -> BrowserState raise WindowSessionError {
  self.with_target("read browser state in", target => {
    match target {
      PrimaryPage(window) => BrowserState::from_native(window.browser_state())
      ChildView(view) => BrowserState::from_native(view.browser_state())
    }
  })
}

///|
/// Reads the main page's session history, corresponding to Electron's
/// `webContents.navigationHistory`.
///
/// Chromium records one history per browser, including entries that the page
/// reached with `history.pushState` only after a navigation; use
/// `WebContentsHandle::back` and `WebContentsHandle::forward` to move through it.
pub fn WebContentsHandle::navigation_history(
  self : WebContentsHandle,
) -> NavigationHistory raise WindowSessionError {
  self.with_target("read navigation history of", target => {
    match target {
      PrimaryPage(window) =>
        NavigationHistory::from_native(window.navigation_history())
      ChildView(view) =>
        NavigationHistory::from_native(view.navigation_history())
    }
  })
}

///|
/// Injects `css` into the current page, corresponding to Electron's
/// `webContents.insertCSS`.
///
/// The returned key removes the stylesheet again with
/// `WebContentsHandle::remove_inserted_css`. Chromium applies the stylesheet to the
/// document that received it, so the key stops matching after the page
/// navigates away, exactly like Electron's.
pub fn WebContentsHandle::insert_css(
  self : WebContentsHandle,
  css : String,
) -> Int64 raise WindowSessionError {
  self.with_target("insert page CSS into", target => {
    match target {
      PrimaryPage(window) => window.insert_page_css(css)
      ChildView(view) => view.insert_page_css(css)
    }
  })
}

///|
/// Removes a stylesheet previously inserted with `WebContentsHandle::insert_css`,
/// corresponding to Electron's `webContents.removeInsertedCSS`. Removing a key
/// the current document never inserted is a no-op.
pub fn WebContentsHandle::remove_inserted_css(
  self : WebContentsHandle,
  key : Int64,
) -> Unit raise WindowSessionError {
  self.with_target("remove page CSS from", target => {
    match target {
      PrimaryPage(window) => window.remove_page_css(key)
      ChildView(view) => view.remove_page_css(key)
    }
  })
}

///|
/// Returns the shared application session. It remains valid after this page
/// closes, until application runtime teardown begins.
pub fn WebContentsHandle::session(self : WebContentsHandle) -> SessionHandle {
  self.session.session_handle()
}

///|
pub fn WebContentsHandle::reload(
  self : WebContentsHandle,
  ignore_cache? : Bool = false,
) -> Unit raise WindowSessionError {
  self.browser_command(
    if ignore_cache {
      "reload_ignore_cache"
    } else {
      "reload"
    },
    None,
  )
}

///|
pub fn WebContentsHandle::stop(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.browser_command("stop", None)
}

///|
/// Undoes the most recent edit in the focused frame.
pub fn WebContentsHandle::undo(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.browser_command("undo", None)
}

///|
/// Redoes the most recently undone edit in the focused frame.
pub fn WebContentsHandle::redo(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.browser_command("redo", None)
}

///|
/// Cuts the current selection in the focused frame.
pub fn WebContentsHandle::cut(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.browser_command("cut", None)
}

///|
/// Copies the current selection in the focused frame.
pub fn WebContentsHandle::copy(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.browser_command("copy", None)
}

///|
/// Pastes clipboard contents into the focused frame.
pub fn WebContentsHandle::paste(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.browser_command("paste", None)
}

///|
/// Pastes clipboard contents using the destination's current style.
pub fn WebContentsHandle::paste_and_match_style(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.browser_command("paste_and_match_style", None)
}

///|
/// Deletes the current selection in the focused frame.
pub fn WebContentsHandle::delete(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.browser_command("delete", None)
}

///|
/// Selects all editable content in the focused frame.
pub fn WebContentsHandle::select_all(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.browser_command("select_all", None)
}

///|
/// Focuses the web page, matching Electron `webContents.focus()`.
pub fn WebContentsHandle::focus(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  let parent = self.session.resolve_window(self.id, self.native_id).window
  self.with_target("focus browser in", target => {
    match target {
      PrimaryPage(window) => {
        window.focus()
        window.browser_command("focus")
      }
      ChildView(view) => {
        // Resolve both identities before focusing the containing window.
        parent.focus()
        view.browser_command("focus")
      }
    }
  })
}

///|
/// Returns whether the web page currently owns focus.
pub fn WebContentsHandle::is_focused(
  self : WebContentsHandle,
) -> Bool raise WindowSessionError {
  self.with_target("read focus of", target => {
    match target {
      PrimaryPage(window) => window.browser_is_focused()
      ChildView(view) => view.browser_is_focused()
    }
  })
}

///|
pub fn WebContentsHandle::open_devtools(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.browser_command("open_devtools", None)
}

///|
pub fn WebContentsHandle::close_devtools(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.browser_command("close_devtools", None)
}

///|
/// Toggles the DevTools view for this web contents.
pub fn WebContentsHandle::toggle_devtools(
  self : WebContentsHandle,
) -> Unit raise WindowSessionError {
  self.browser_command("toggle_devtools", None)
}

///|
/// Returns whether this web contents currently has an open DevTools view.
pub fn WebContentsHandle::is_devtools_opened(
  self : WebContentsHandle,
) -> Bool raise WindowSessionError {
  self.with_target("read DevTools state of", target => {
    match target {
      PrimaryPage(window) => window.is_devtools_opened()
      ChildView(view) => view.is_devtools_opened()
    }
  })
}

///|
pub fn WebContentsHandle::cancel_download(
  self : WebContentsHandle,
  download_id : Int,
) -> Unit raise WindowSessionError {
  self.browser_command("cancel_download", Some(download_id))
}

///|
fn RuntimeSession::command_host(self : RuntimeSession) -> @core.AppCommandHost? {
  self.command_host.map(host => host.host)
}

///|
async fn RuntimeSession::wait_for_bridge_startup(
  self : RuntimeSession,
  timeout_ms : Int,
) -> Unit {
  let completed = @async.with_timeout_opt(timeout_ms, () => {
    drive_wakeup_until(
      self.wakeup,
      () => {
        self.is_quitting() ||
        refresh_bridge_startup_states(self.windows) is None
      },
      () => self.pump_once(monitor_bridge=false),
    )
  })
  match completed {
    Some(_) => ()
    None => {
      ignore(self.pump_once(monitor_bridge=false))
      if self.is_quitting() {
        return
      }
      match refresh_bridge_startup_states(self.windows) {
        None => return
        Some(state) =>
          raise BridgeStartupError(
            BridgeDiagnostic::from_native(
              bridge_startup_timeout_diagnostic(state, timeout_ms),
            ),
          )
      }
    }
  }
}

///|
async fn RuntimeSession::run(self : RuntimeSession) -> Unit {
  drive_wakeup_until(self.wakeup, () => self.quit_complete(), () => {
    self.pump_once(monitor_bridge=self.monitor_bridge)
  })
  self.cancel_all_bridge_tasks()
  self.close_coordinator.cancel_all()
  self.cancel_all_browser_requests()
  self.cancel_all_resource_requests()
}

///|
priv enum StartupTaskOutcome {
  Completed
  Stopped
}

///|
async fn RuntimeSession::drive_until_complete(
  self : RuntimeSession,
  task : @async.Task[Unit],
) -> StartupTaskOutcome {
  drive_wakeup_until(
    self.wakeup,
    () => {
      if self.quit_complete() {
        task.cancel()
        return true
      }
      let completed = task.try_wait() catch {
        error => raise normalize_async_run_error(error)
      }
      // A completed hook does not resolve an outstanding quit decision.
      // Denial resumes startup; commitment must finish shutdown first.
      completed is Some(_) && self.close_coordinator.state == CloseRunning
    },
    () => self.pump_once(monitor_bridge=self.monitor_bridge),
  )
  if self.quit_complete() {
    Stopped
  } else {
    Completed
  }
}

///|
fn RuntimeSession::pump_once(
  self : RuntimeSession,
  monitor_bridge? : Bool = true,
) -> Bool raise AppRunError {
  let mut did_work = self.process_window_commands()
  if self.drain_runtime_events() {
    did_work = true
  }
  if self.drain_extension_events() {
    did_work = true
  }
  if monitor_bridge {
    self.check_bridge_failures()
  }
  if self.complete_bridge_requests() {
    did_work = true
  }
  if self.advance_window_opens() {
    did_work = true
  }
  if self.complete_browser_requests() {
    did_work = true
  }
  if self.complete_resource_requests() {
    did_work = true
  }
  if self.advance_application_lifetime() {
    did_work = true
  }
  did_work
}

///|
fn RuntimeSession::start_extension_event_sources(
  self : RuntimeSession,
) -> Unit raise AppRunError {
  match self.command_host {
    None => ()
    Some(host) =>
      start_command_extension_event_sources(
        host.event_sources,
        @native.event_wakeup_callback(),
      )
  }
}

///|
fn start_command_extension_event_sources(
  event_sources : Array[CommandExtensionEventSource],
  wakeup : @proton_extension.EventWakeup,
) -> Unit raise AppRunError {
  for event_source in event_sources {
    guard !event_source.started else { continue }
    event_source.started = true
    event_source.source.start(wakeup) catch {
      error => {
        event_source.source.stop()
        event_source.started = false
        raise CommandExtensionLifecycleError(
          EventSourceStartFailed(
            extension_id=event_source.extension_id,
            detail=@debug.render(Repr(error)),
          ),
        )
      }
    }
  }
}

///|
fn RuntimeSession::drain_extension_events(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  let mut did_work = false
  match self.command_host {
    None => ()
    Some(host) =>
      for event_source in host.event_sources {
        guard event_source.started else { continue }
        let events = event_source.drain()
        if !events.is_empty() {
          did_work = true
        }
        for event in events {
          guard event.extension_id() == event_source.extension_id &&
            event.extension_namespace() == event_source.extension_namespace else {
            event_source.disable(
              "event descriptor belongs to " +
              event.extension_id() +
              " (" +
              event.extension_namespace() +
              ")",
            )
            break
          }
          self.forward_extension_event_to_granted_windows(
            event_source.extension_id,
            event_source.extension_namespace,
            event.name(),
            event.payload(),
          )
        }
      }
  }
  did_work
}

///|
fn CommandExtensionEventSource::drain(
  self : CommandExtensionEventSource,
) -> Array[@proton_extension.Event] {
  guard self.started else { return [] }
  self.source.drain() catch {
    error => {
      self.disable(@debug.render(Repr(error)))
      []
    }
  }
}

///|
fn CommandExtensionEventSource::disable(
  self : CommandExtensionEventSource,
  detail : String,
) -> Unit {
  self.stop()
  @xlog.error(category="proton.extension") <?
    {
      "message": "event source disabled",
      "extension_id": self.extension_id,
      "detail": detail,
    }
}

///|
fn RuntimeSession::forward_extension_event_to_granted_windows(
  self : RuntimeSession,
  extension_id : String,
  extension_namespace : String,
  name : String,
  payload : Json,
) -> Unit raise AppRunError {
  for running in self.windows {
    guard running.is_active() &&
      running.bridge_ready &&
      running.permissions.grants_extension(extension_id) else {
      continue
    }
    forward_extension_event(running.window, extension_namespace, name, payload)
  }
}

///|
fn RuntimeSession::drain_runtime_events(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  self.event_pump.drain_session_events(event => {
    self.dispatch_runtime_event(event)
  })
}

///|
fn RuntimeSession::dispatch_runtime_event(
  self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit raise AppRunError {
  if event.is_quit_requested() {
    self.request_quit(0)
  }
  self.dispatch_window_event(event)
  self.dispatch_view_event(event)
  self.dispatch_browser_event(event)
  self.dispatch_resource_event(event)
  self.dispatch_notification_event(event)
  self.dispatch_launch_input_event(event)
  self.dispatch_system_appearance_event(event)
  self.dispatch_thumbar_button_event(event)
  self.dispatch_menu_event(event)
  match event.bridge_request() {
    Some(request) => self.start_bridge_request(request)
    None => ()
  }
  self.cancel_bridge_request(event.bridge_request_cancellation())
}

///|
fn RuntimeSession::dispatch_window_event(
  self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit raise AppRunError {
  if event.is_window_closed() {
    let window_id = event.window_id()
    match window_id {
      Some(window_id) =>
        match self.find_window_by_native_id(window_id) {
          Some(window) => {
            let handle = self.window_handle(window)
            for handler in self.config.contents_event_handlers {
              ignore(
                self.window_tasks.spawn(
                  () => handler(handle.web_contents(), Closed),
                  no_wait=true,
                ),
              )
            }
            for handler in self.config.window_event_handlers {
              ignore(
                self.window_tasks.spawn(
                  () => handler(handle, Closed),
                  no_wait=true,
                ),
              )
            }
          }
          None => ()
        }
      None => ()
    }
    runtime_session_cancel_window_bridge_tasks(self.pending_bridge, window_id)
    self.close_coordinator.cancel(window_id)
    self.cancel_browser_requests(window_id)
    self.cancel_resource_requests_for_window(window_id)
    self.retire_closed_window(window_id)
    return
  }
  match (event.window_id(), event.window_state_change()) {
    (Some(window_id), Some(state)) =>
      match self.find_window_by_native_id(window_id) {
        Some(window) => {
          let handle = self.window_handle(window)
          let current = WindowState::from_native(state)
          let events = window_state_events(window.observed_state, current)
          window.observed_state = Some(current)
          for event in events {
            for handler in self.config.window_event_handlers {
              ignore(
                self.window_tasks.spawn(
                  () => handler(handle, event),
                  no_wait=true,
                ),
              )
            }
          }
        }
        None => ()
      }
    _ => ()
  }
  match (event.window_id(), event.window_close_request()) {
    (Some(window_id), Some(request_id)) =>
      self.start_window_close_request(window_id, request_id)
    _ => ()
  }
}

///|
fn RunningWindow::find_view_by_native_id(
  self : RunningWindow,
  id : Int64,
) -> RunningView? {
  for view in self.views {
    if view.native_id == id {
      return Some(view)
    }
  }
  None
}

///|
fn RuntimeSession::contents_handle(
  self : RuntimeSession,
  window : RunningWindow,
  view_id : Int64?,
) -> WebContentsHandle? {
  match view_id {
    None => Some(self.browser_handle(window))
    Some(id) =>
      match window.find_view_by_native_id(id) {
        Some(view) => Some(self.view_handle(window, view).web_contents())
        None => None
      }
  }
}

///|
fn RuntimeSession::dispatch_view_event(
  self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit raise AppRunError {
  guard event.is_view_closed() else { return }
  guard event.window_id() is Some(window_id) else { return }
  guard event.view_id() is Some(view_id) else { return }
  guard self.find_window_by_native_id(window_id) is Some(window) else { return }
  self.cancel_contents_browser_requests(window_id, Some(view_id))
  for index, view in window.views {
    if view.native_id == view_id {
      let contents = self.view_handle(window, view).web_contents()
      view.view.destroy() catch {
        error =>
          raise native_run_error(
            "destroy closed view " + view.id + " in window " + window.id,
            error,
          )
      }
      ignore(window.views.remove(index))
      for handler in self.config.contents_event_handlers {
        ignore(
          self.window_tasks.spawn(() => handler(contents, Closed), no_wait=true),
        )
      }
      return
    }
  }
}

///|
fn RuntimeSession::dispatch_browser_event(
  self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit raise AppRunError {
  match
    (
      event.window_id(),
      event.browser_event(),
      event.renderer_process_termination(),
      event.find_in_page_result(),
    ) {
    (Some(window_id), info, termination, find_result) =>
      match self.find_window_by_native_id(window_id) {
        Some(window) => {
          if termination is Some(_) {
            match event.view_id() {
              None => self.fail_page_requests(window)
              Some(_) => self.fail_contents_requests(window, event.view_id())
            }
          }
          guard self.contents_handle(window, event.view_id()) is Some(browser) else {
            return
          }
          let observed = match
            (event.event_type(), info, termination, find_result) {
            ("browser_loading_changed", Some(info), _, _) => {
              let is_loading = info.is_loading.unwrap_or(false)
              let view = match event.view_id() {
                Some(id) => window.find_view_by_native_id(id)
                None => None
              }
              let previous = match view {
                Some(view) => view.observed_loading
                None => window.observed_browser_loading
              }
              let transition = match previous {
                None => []
                Some(previous) =>
                  if !previous && is_loading {
                    [WebContentsEvent::DidStartLoading]
                  } else if previous && !is_loading {
                    [WebContentsEvent::DidFinishLoad]
                  } else {
                    []
                  }
              }
              match view {
                Some(view) => view.observed_loading = Some(is_loading)
                None => window.observed_browser_loading = Some(is_loading)
              }
              for transition_event in transition {
                for handler in self.config.contents_event_handlers {
                  ignore(
                    self.window_tasks.spawn(
                      () => handler(browser, transition_event),
                      no_wait=true,
                    ),
                  )
                }
              }
              Some(WebContentsEvent::LoadingChanged(is_loading~))
            }
            ("browser_navigated", Some(info), _, _) =>
              Some(WebContentsEvent::Navigated(url=info.url.unwrap_or("")))
            ("browser_title_updated", Some(info), _, _) =>
              Some(
                WebContentsEvent::TitleUpdated(title=info.title.unwrap_or("")),
              )
            ("browser_load_failed", Some(info), _, _) =>
              Some(
                WebContentsEvent::LoadFailed(
                  url=info.url.unwrap_or(""),
                  error_code=info.error_code.unwrap_or(0),
                  error_text=info.error_text.unwrap_or(""),
                ),
              )
            ("browser_found_in_page", _, _, Some(result)) =>
              Some(
                WebContentsEvent::FoundInPage(
                  result=FindInPageResult::from_native(result),
                ),
              )
            ("browser_resource_response", Some(info), _, _) =>
              Some(
                WebContentsEvent::ResourceResponse(
                  url=info.url.unwrap_or(""),
                  status_code=info.error_code.unwrap_or(0),
                ),
              )
            ("browser_resource_requested", Some(info), _, _) =>
              Some(
                WebContentsEvent::ResourceRequested(
                  url=info.url.unwrap_or(""),
                  request_method=info.title.unwrap_or(""),
                  will_cancel=info.is_loading.unwrap_or(false),
                ),
              )
            ("browser_resource_completed", Some(info), _, _) =>
              Some(
                WebContentsEvent::ResourceCompleted(
                  url=info.url.unwrap_or(""),
                  status=info.error_code.unwrap_or(0),
                  received_bytes=info.received_bytes.unwrap_or(0L),
                ),
              )
            ("browser_renderer_process_terminated", _, Some(details), _) =>
              Some(
                WebContentsEvent::RendererProcessTerminated(
                  url=details.url,
                  status=details.status,
                  error_code=details.error_code,
                  detail=details.detail,
                ),
              )
            _ => None
          }
          match observed {
            Some(observed) =>
              for handler in self.config.contents_event_handlers {
                ignore(
                  self.window_tasks.spawn(
                    () => handler(browser, observed),
                    no_wait=true,
                  ),
                )
              }
            None => ()
          }
          match observed {
            Some(RendererProcessTerminated(status~, error_code~, ..)) =>
              self.emit_render_process_gone(browser, RenderProcessGoneDetails::{
                reason: render_process_gone_reason(status),
                exit_code: error_code,
              })
            _ => ()
          }
        }
        None => ()
      }
    _ => ()
  }
  match event.browser_request() {
    Some(request) =>
      self.start_browser_request(event.window_id(), event.view_id(), request)
    None => ()
  }
  match (event.window_id(), event.browser_download_update()) {
    (Some(window_id), Some(update)) =>
      match self.find_window_by_native_id(window_id) {
        Some(window) => {
          guard self.contents_handle(window, event.view_id()) is Some(browser) else {
            return
          }
          let observed = DownloadEvent::{
            id: update.download_id,
            state: update.state,
            received_bytes: update.received_bytes,
            total_bytes: update.total_bytes,
            percent: update.percent,
          }
          for handler in self.config.download_event_handlers {
            ignore(
              self.window_tasks.spawn(
                () => handler(browser, observed),
                no_wait=true,
              ),
            )
          }
        }
        None => ()
      }
    _ => ()
  }
}

///|
fn RuntimeSession::start_browser_request(
  self : RuntimeSession,
  window_id : Int64?,
  view_id : Int64?,
  request : @native.NativeBrowserRequest,
) -> Unit {
  guard window_id is Some(window_id) else { return }
  guard self.find_window_by_native_id(window_id) is Some(window) else { return }
  guard self.contents_handle(window, view_id) is Some(browser) else { return }
  let request_id = match request {
    Navigation(request_id~, ..)
    | NewWindow(request_id~, ..)
    | Download(request_id~, ..)
    | Certificate(request_id~, ..)
    | Media(request_id~, ..) => request_id
  }
  let task = self.window_tasks.spawn(
    () => {
      defer self.wakeup.signal.notify()
      match request {
        Navigation(url~, http_method~, user_gesture~, redirect~, ..) =>
          match self.config.navigation_handler {
            Some(handler) =>
              match
                handler(browser, { url, http_method, user_gesture, redirect, }) {
                NavigationDecision::Allow =>
                  BrowserResponse::{ action: "allow", path: None, }
                NavigationDecision::Deny =>
                  BrowserResponse::{ action: "deny", path: None, }
              }
            None => BrowserResponse::{ action: "deny", path: None, }
          }
        NewWindow(url~, user_gesture~, ..) => {
          let decision = match self.config.new_window_handler {
            Some(handler) => handler(browser, { url, user_gesture, })
            None => NewWindowDecision::Deny
          }
          match decision {
            NewWindowDecision::Deny => ()
            NewWindowDecision::OpenInCurrent =>
              browser.load_url(url) catch {
                _ => ()
              }
            NewWindowDecision::OpenInWindow(id) => {
              let opened = Some(self.window_manager().open(id)) catch {
                _ => None
              }
              match opened {
                Some(window) =>
                  window.web_contents().load_url(url) catch {
                    _ => ()
                  }
                None => ()
              }
            }
          }
          BrowserResponse::{ action: "deny", path: None, }
        }
        Download(download_id~, url~, suggested_name~, ..) =>
          match self.config.download_handler {
            Some(handler) =>
              match
                handler(browser, { id: download_id, url, suggested_name, }) {
                DownloadDecision::Deny =>
                  BrowserResponse::{ action: "deny", path: None, }
                DownloadDecision::ShowSaveDialog =>
                  BrowserResponse::{ action: "allow", path: None, }
                DownloadDecision::SaveTo(path) =>
                  BrowserResponse::{ action: "allow", path: Some(path), }
              }
            None => BrowserResponse::{ action: "deny", path: None, }
          }
        Certificate(url~, error_code~, ..) =>
          match self.config.permission_handler {
            Some(handler) =>
              match
                handler(
                  browser,
                  PermissionRequest::Certificate({ url, error_code, }),
                ) {
                BrowserPermissionDecision::Allow =>
                  BrowserResponse::{ action: "allow", path: None, }
                BrowserPermissionDecision::Deny =>
                  BrowserResponse::{ action: "deny", path: None, }
              }
            None =>
              match self.config.certificate_handler {
                Some(handler) =>
                  match handler(browser, { url, error_code, }) {
                    BrowserPermissionDecision::Allow =>
                      BrowserResponse::{ action: "allow", path: None, }
                    BrowserPermissionDecision::Deny =>
                      BrowserResponse::{ action: "deny", path: None, }
                  }
                None => BrowserResponse::{ action: "deny", path: None, }
              }
          }
        Media(origin~, permissions~, ..) =>
          match self.config.permission_handler {
            Some(handler) =>
              match
                handler(
                  browser,
                  PermissionRequest::Media({ origin, permissions, }),
                ) {
                BrowserPermissionDecision::Allow =>
                  BrowserResponse::{ action: "allow", path: None, }
                BrowserPermissionDecision::Deny =>
                  BrowserResponse::{ action: "deny", path: None, }
              }
            None =>
              match self.config.media_handler {
                Some(handler) =>
                  match handler(browser, { origin, permissions, }) {
                    BrowserPermissionDecision::Allow =>
                      BrowserResponse::{ action: "allow", path: None, }
                    BrowserPermissionDecision::Deny =>
                      BrowserResponse::{ action: "deny", path: None, }
                  }
                None => BrowserResponse::{ action: "deny", path: None, }
              }
          }
      }
    },
    no_wait=true,
  )
  self.pending_browser_requests.push({
    window: window_id,
    view: view_id,
    request_id,
    task,
  })
}

///|
fn RunningWindow::respond_contents_request(
  self : RunningWindow,
  view_id : Int64?,
  request_id : Int64,
  action : String,
  path? : String,
) -> Unit raise @native.NativeError {
  match view_id {
    None => self.window.respond_browser_request(request_id, action, path?)
    Some(id) =>
      match self.find_view_by_native_id(id) {
        Some(view) if view.view.id() != 0 =>
          view.view.respond_browser_request(request_id, action, path?)
        _ => ()
      }
  }
}

///|
fn RuntimeSession::fail_contents_requests(
  self : RuntimeSession,
  window : RunningWindow,
  view_id : Int64?,
) -> Unit raise AppRunError {
  for pending in self.pending_browser_requests {
    if pending.window == window.native_id && pending.view == view_id {
      window.respond_contents_request(view_id, pending.request_id, "deny") catch {
        error =>
          if !error.is_stale_browser_request() &&
            !error.is_stale_window_request() {
            raise native_run_error("reject failed page request", error)
          }
      }
    }
  }
  self.cancel_contents_browser_requests(window.native_id, view_id)
  let remaining : Array[PendingResourceRequest] = []
  for pending in self.pending_resource_requests {
    if pending.window == window.native_id && pending.view == view_id {
      self.runtime.complete_resource_request(
        pending.request_id,
        503,
        "text/plain",
        b"",
      ) catch {
        error =>
          if !error.is_stale_resource_request() {
            raise native_run_error("reject failed page resource", error)
          }
      }
      pending.task.cancel()
    } else {
      remaining.push(pending)
    }
  }
  self.pending_resource_requests.clear()
  for pending in remaining {
    self.pending_resource_requests.push(pending)
  }
}

///|
fn RuntimeSession::complete_browser_requests(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  let remaining : Array[PendingBrowserRequest] = []
  let mut did_work = false
  for pending in self.pending_browser_requests {
    let completed = pending.task.try_wait() catch {
      _ => Some(BrowserResponse::{ action: "deny", path: None, })
    }
    match completed {
      None => remaining.push(pending)
      Some(response) => {
        did_work = true
        match self.find_window_by_native_id(pending.window) {
          Some(window) if window.is_active() => {
            let path = response.path
            window.respond_contents_request(
              pending.view,
              pending.request_id,
              response.action,
              path?,
            ) catch {
              error =>
                if !error.is_stale_browser_request() &&
                  !error.is_stale_window_request() {
                  raise native_run_error("respond to browser request", error)
                }
            }
          }
          _ => ()
        }
      }
    }
  }
  self.pending_browser_requests.clear()
  for pending in remaining {
    self.pending_browser_requests.push(pending)
  }
  did_work
}

///|
fn RuntimeSession::cancel_browser_requests(
  self : RuntimeSession,
  window_id : Int64?,
) -> Unit {
  let remaining : Array[PendingBrowserRequest] = []
  for pending in self.pending_browser_requests {
    if window_id == Some(pending.window) {
      pending.task.cancel()
    } else {
      remaining.push(pending)
    }
  }
  self.pending_browser_requests.clear()
  for pending in remaining {
    self.pending_browser_requests.push(pending)
  }
}

///|
fn RuntimeSession::cancel_contents_browser_requests(
  self : RuntimeSession,
  window : Int64,
  view : Int64?,
) -> Unit {
  let remaining : Array[PendingBrowserRequest] = []
  for pending in self.pending_browser_requests {
    if pending.window == window && pending.view == view {
      pending.task.cancel()
    } else {
      remaining.push(pending)
    }
  }
  self.pending_browser_requests.clear()
  for pending in remaining {
    self.pending_browser_requests.push(pending)
  }
}

///|
fn RuntimeSession::cancel_all_browser_requests(self : RuntimeSession) -> Unit {
  for pending in self.pending_browser_requests {
    pending.task.cancel()
  }
  self.pending_browser_requests.clear()
}

///|
fn RuntimeSession::dispatch_resource_event(
  self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit {
  match event.resource_request() {
    Some(request) => self.start_resource_request(request)
    None => ()
  }
  self.cancel_resource_request(event.resource_request_cancellation())
}

///|
fn RuntimeSession::start_resource_request(
  self : RuntimeSession,
  request : @native.NativeResourceRequest,
) -> Unit {
  let (document, asset_root) = match
    self.find_window_by_native_id(request.window) {
    Some(window) if request.view is Some(view_id) => {
      let mut document = None
      for view in window.views {
        if view.view.id() == view_id {
          document = view.document
          break
        }
      }
      (document, None)
    }
    Some(window) => (window.document, window.asset_root)
    None => (None, None)
  }
  let task = self.window_tasks.spawn(
    () => {
      defer self.wakeup.signal.notify()
      resolve_resource_request(document, asset_root, request.url)
    },
    no_wait=true,
  )
  self.pending_resource_requests.push({
    request_id: request.request_id,
    window: request.window,
    view: request.view,
    task,
  })
}

///|
fn RuntimeSession::complete_resource_requests(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  let remaining : Array[PendingResourceRequest] = []
  let mut did_work = false
  for pending in self.pending_resource_requests {
    let completed = pending.task.try_wait() catch {
      _ => Some(resource_text_response(500, "Resource request failed"))
    }
    match completed {
      None => remaining.push(pending)
      Some(response) => {
        did_work = true
        self.runtime.complete_resource_request(
          pending.request_id,
          response.status,
          response.mime_type,
          response.body,
        ) catch {
          error =>
            if !error.is_stale_resource_request() {
              raise native_run_error("complete resource request", error)
            }
        }
      }
    }
  }
  self.pending_resource_requests.clear()
  for pending in remaining {
    self.pending_resource_requests.push(pending)
  }
  did_work
}

///|
fn RuntimeSession::cancel_resource_request(
  self : RuntimeSession,
  request_id : Int64?,
) -> Unit {
  guard request_id is Some(request_id) else { return }
  let remaining : Array[PendingResourceRequest] = []
  for pending in self.pending_resource_requests {
    if pending.request_id == request_id {
      pending.task.cancel()
    } else {
      remaining.push(pending)
    }
  }
  self.pending_resource_requests.clear()
  for pending in remaining {
    self.pending_resource_requests.push(pending)
  }
}

///|
fn RuntimeSession::cancel_resource_requests_for_window(
  self : RuntimeSession,
  window_id : Int64?,
) -> Unit {
  guard window_id is Some(window_id) else { return }
  let remaining : Array[PendingResourceRequest] = []
  for pending in self.pending_resource_requests {
    if pending.window == window_id {
      pending.task.cancel()
    } else {
      remaining.push(pending)
    }
  }
  self.pending_resource_requests.clear()
  for pending in remaining {
    self.pending_resource_requests.push(pending)
  }
}

///|
fn RuntimeSession::cancel_all_resource_requests(self : RuntimeSession) -> Unit {
  for pending in self.pending_resource_requests {
    pending.task.cancel()
  }
  self.pending_resource_requests.clear()
}

///|
fn RuntimeSession::start_window_close_request(
  self : RuntimeSession,
  window_id : Int64,
  request_id : Int64,
) -> Unit {
  guard self.config.window_close_handler is Some(handler) else { return }
  guard self.find_window_by_native_id(window_id) is Some(window) else { return }
  match self.close_coordinator.find(window_id) {
    Some(pending) => {
      pending.native_request = Some(request_id)
      return
    }
    None => ()
  }
  // A pending decision does not revoke access to the live window.
  let handle = self.window_handle(window)
  let task = self.window_tasks.spawn(
    () => {
      defer self.wakeup.signal.notify()
      handler(handle)
    },
    no_wait=true,
  )
  self.close_coordinator.pending.push(PendingCloseDecision::{
    window: window_id,
    task,
    decision: None,
    native_request: Some(request_id),
  })
}

///|
fn RuntimeSession::advance_individual_close_decisions(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  let remaining : Array[PendingCloseDecision] = []
  let mut did_work = false
  for pending in self.close_coordinator.pending {
    let completed = pending.task.try_wait() catch { _ => Some(Allow) }
    match completed {
      None => remaining.push(pending)
      Some(decision) => {
        did_work = true
        self.respond_close_decision(pending, decision)
      }
    }
  }
  self.close_coordinator.pending.clear()
  for pending in remaining {
    self.close_coordinator.pending.push(pending)
  }
  did_work
}

///|
fn RuntimeSession::dispatch_notification_event(
  self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit raise AppRunError {
  match event.notification_result() {
    Some(result) => publish_notification_result(result)
    None => ()
  }
  match event.notification_click() {
    Some(payload) =>
      for running in preferred_active_windows(self.windows) {
        guard running.is_active() &&
          running.bridge_ready &&
          running.permissions.grants_extension(notification_extension_id) else {
          continue
        }
        forward_extension_event(
          running.window,
          notification_extension_namespace,
          "click",
          notification_click_payload(payload),
        )
        break
      }
    None => ()
  }
}

///|
fn RuntimeSession::dispatch_launch_input_event(
  self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit raise AppRunError {
  match event.app_activation() {
    Some(activation) => {
      let request_id = event.app_activation_request_id()
      if request_id != 0 {
        let accepted = self.runtime.respond_app_activation(
          request_id,
          !self.is_quitting(),
        ) catch {
          error => raise native_run_error("respond to app activation", error)
        }
        guard accepted else { return }
      }
      let urls = activation.urls()
      if !urls.is_empty() {
        self.dispatch_launch_input(RuntimeLaunchInput::OpenUrls(urls))
      }
      let files = activation.files()
      if !files.is_empty() {
        self.dispatch_launch_input(RuntimeLaunchInput::OpenFiles(files))
      }
      if activation.reopen() {
        self.dispatch_launch_input(RuntimeLaunchInput::Reopen)
      }
    }
    None =>
      match event.launch_input() {
        Some(native_input) =>
          self.dispatch_launch_input(
            match native_input {
              @native.RuntimeLaunchInput::OpenUrls(urls) =>
                RuntimeLaunchInput::OpenUrls(urls)
              @native.RuntimeLaunchInput::OpenFiles(files) =>
                RuntimeLaunchInput::OpenFiles(files)
              @native.RuntimeLaunchInput::Reopen => RuntimeLaunchInput::Reopen
            },
          )
        None => ()
      }
  }
}

///|
fn RuntimeSession::dispatch_launch_input(
  self : RuntimeSession,
  input : RuntimeLaunchInput,
) -> Unit raise AppRunError {
  guard !self.is_quitting() else { return }
  self.activate_for_launch_input()
  let context = self.application_context()
  for handler in self.config.launch_input_handlers {
    ignore(
      self.application_tasks.spawn(() => handler(context, input), no_wait=true),
    )
  }
}

///|
fn RuntimeSession::activate_for_launch_input(
  self : RuntimeSession,
) -> Unit raise AppRunError {
  for running in preferred_active_windows(self.windows) {
    if try_activate_window_for_launch_input(running) {
      return
    }
  }
}

///|
fn try_activate_window_for_launch_input(
  running : RunningWindow,
) -> Bool raise AppRunError {
  try_activate_for_launch_input(
    () => running.window.state(),
    () => running.window.restore(),
    () => running.window.show(),
    () => running.window.focus(),
  )
}

///|
fn try_activate_for_launch_input(
  read_state : () -> @native.WindowState raise @native.NativeError,
  restore : () -> Unit raise @native.NativeError,
  show : () -> Unit raise @native.NativeError,
  focus : () -> Unit raise @native.NativeError,
) -> Bool raise AppRunError {
  let state = read_state() catch {
    error => {
      if error.is_invalid_state() || error.is_stale_window_request() {
        return false
      }
      raise native_run_error("read activation window state", error)
    }
  }
  if state.minimized {
    restore() catch {
      error => {
        if error.is_invalid_state() || error.is_stale_window_request() {
          return false
        }
        raise native_run_error("restore activation window", error)
      }
    }
  }
  if !state.visible {
    show() catch {
      error => {
        if error.is_invalid_state() || error.is_stale_window_request() {
          return false
        }
        raise native_run_error("show activation window", error)
      }
    }
  }
  focus() catch {
    error => {
      if error.is_invalid_state() || error.is_stale_window_request() {
        return false
      }
      raise native_run_error("focus activation window", error)
    }
  }
  true
}

///|
/// Applies the thumbnail-toolbar buttons and reports whether the taskbar
/// showed them.
fn RuntimeSession::set_window_thumbar_buttons(
  self : RuntimeSession,
  id : String,
  native_id : Int64,
  buttons : Array[@native.ThumbarButton],
) -> Bool raise WindowSessionError {
  let running = self.resolve_window(id, native_id)
  running.window.set_thumbar_buttons(buttons) catch {
    error =>
      raise window_operation_failed("set taskbar buttons in " + id, error)
  }
}

///|
/// Forwards a taskbar thumbnail-toolbar click to the application handlers with
/// the window that owns the toolbar and the button identifier.
fn RuntimeSession::dispatch_thumbar_button_event(
  self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit {
  match event.taskbar_button_id() {
    Some(button_id) =>
      match event.window_id() {
        Some(window_id) =>
          match self.find_window_by_native_id(window_id) {
            Some(window) => {
              let handle = self.window_handle(window)
              for handler in self.config.thumbar_button_handlers {
                ignore(
                  self.application_tasks.spawn(
                    () => handler(handle, button_id),
                    no_wait=true,
                  ),
                )
              }
            }
            None => ()
          }
        None => ()
      }
    None => ()
  }
}

///|
/// Forwards an operating system appearance change to the application
/// handlers with the captured system appearance snapshot.
fn RuntimeSession::dispatch_system_appearance_event(
  self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit {
  match event.native_theme_change() {
    Some(snapshot) => {
      let theme = SystemAppearance::from_native(snapshot)
      for handler in self.config.system_appearance_handlers {
        ignore(self.application_tasks.spawn(() => handler(theme), no_wait=true))
      }
    }
    None => ()
  }
}

///|
fn RuntimeSession::dispatch_menu_event(
  self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit raise AppRunError {
  guard self.forward_menu_events else { return }
  match event.menu_command_id() {
    Some(command_id) => self.forward_menu_command(command_id, event.window_id())
    None => ()
  }
}

///|
/// The bridge diagnostic a renderer termination records. Proton reports it
/// through `on_render_process_gone` instead of failing the run.
let renderer_process_terminated_failure_code = "renderer_process_terminated"

///|
fn RuntimeSession::check_bridge_failures(
  self : RuntimeSession,
) -> Unit raise AppRunError {
  guard !self.is_quitting() else { return }
  for running in self.windows {
    // Startup failures remain owned by the opening operation.
    guard running.state is WindowOpen else { continue }
    let state = running.window.bridge_lifecycle_state() catch {
      error =>
        raise native_run_error("read bridge state for " + running.id, error)
    }
    guard state is Some(state) else {
      running.bridge_ready = false
      continue
    }
    running.bridge_ready = state.outcome == "ready"
    guard state.failure_pending else { continue }
    let diagnostic = bridge_failure(running.window, state) catch {
      error =>
        raise native_run_error("read bridge failure for " + running.id, error)
    }
    self.fail_page_requests(running)
    @xlog.warn(category="proton.bridge") <?
      {
        "message": "page bridge failed",
        "window": running.id,
        "code": diagnostic.code,
        "url": diagnostic.url,
        "detail": diagnostic.message,
      }
    // Renderer failure has its own notification; do not report it twice.
    if diagnostic.code != renderer_process_terminated_failure_code {
      let browser = self.browser_handle(running)
      let event = WebContentsEvent::BridgeFailed(
        diagnostic=BridgeDiagnostic::from_native(diagnostic),
      )
      for handler in self.config.contents_event_handlers {
        ignore(
          self.window_tasks.spawn(() => handler(browser, event), no_wait=true),
        )
      }
    }
  }
}

///|
fn RuntimeSession::fail_page_requests(
  self : RuntimeSession,
  running : RunningWindow,
) -> Unit raise AppRunError {
  running.bridge_ready = false
  runtime_session_cancel_window_bridge_tasks(
    self.pending_bridge,
    Some(running.native_id),
  )
  self.fail_contents_requests(running, None)
}

///|
fn RuntimeSession::start_bridge_request(
  self : RuntimeSession,
  request : @native.BridgeRequest,
) -> Unit raise AppRunError {
  let request_id = request.request_id()
  let target = match self.find_window_by_native_id(request.window()) {
    Some(window) if window.is_active() => window
    _ => {
      self.respond_bridge_request(
        @native.BridgeResponse::Err(
          detail=None,
          request_id~,
          code="window_closed",
          message="the issuing window is no longer available",
        ),
        "reject bridge request",
      )
      return
    }
  }
  match self.command_host() {
    None =>
      self.respond_bridge_request(
        @native.BridgeResponse::Err(
          detail=None,
          request_id~,
          code="command_host_unavailable",
          message="the application command host is not available",
        ),
        "reject bridge request",
      )
    Some(host) => {
      let task = self.window_tasks.spawn(
        () => {
          defer self.wakeup.signal.notify()
          dispatch_bridge_request(
            self.runtime,
            target.window,
            target.id,
            target.permissions,
            host,
            request,
            self.wakeup.signal,
            self.event_pump.dialog_completions,
            self.environment.locale_preferences,
          )
        },
        no_wait=true,
        allow_failure=true,
      )
      self.pending_bridge.push(BridgeDispatchTask::{
        request_id,
        window: target.native_id,
        task,
        state: Running,
      })
    }
  }
}

///|
fn RuntimeSession::respond_bridge_request(
  self : RuntimeSession,
  response : @native.BridgeResponse,
  action : String,
) -> Unit raise AppRunError {
  self.runtime.respond_bridge_request(response) catch {
    error =>
      if !is_stale_bridge_response_error(error) {
        raise native_run_error(action, error)
      }
  }
}

///|
fn RuntimeSession::complete_bridge_requests(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  let remaining : Array[BridgeDispatchTask] = []
  let mut did_work = false
  for item in self.pending_bridge {
    if item.state == Cancelled {
      continue
    }
    let completed = item.task.try_wait() catch {
      error => raise normalize_async_run_error(error)
    }
    match completed {
      Some(None) => {
        did_work = true
        item.state = Stale
      }
      Some(Some(response)) => {
        did_work = true
        item.state = Responding
        self.runtime.respond_bridge_request(response) catch {
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
  self.pending_bridge.clear()
  for item in remaining {
    self.pending_bridge.push(item)
  }
  did_work
}

///|
fn RuntimeSession::find_window_by_native_id(
  self : RuntimeSession,
  window_id : Int64,
) -> RunningWindow? {
  for running in self.windows {
    if running.native_id == window_id {
      return Some(running)
    }
  }
  None
}

///|
fn RuntimeSession::retire_closed_window(
  self : RuntimeSession,
  window_id : Int64?,
) -> Unit raise AppRunError {
  guard window_id is Some(window_id) else { return }
  guard self.find_window_by_native_id(window_id) is Some(running) else {
    return
  }
  self.retire_window(running) catch {
    error => raise CleanupFailed(primary=None, failures=[error])
  }
}

///|
fn RuntimeSession::retire_window(
  self : RuntimeSession,
  running : RunningWindow,
) -> Unit raise AppCleanupError {
  running.state = WindowClosed
  running.lifetime.close()
  running.window.destroy() catch {
    error =>
      raise WindowDestroy(
        status=error.status(),
        detail="destroy window " + running.id + ": " + error.message(),
      )
  }
  // Destruction clears the native ID. Unregister only this instance after
  // success; on failure, retain it for app_cleanup to retry destruction.
  for index, registered in self.windows {
    if physical_equal(registered, running) {
      ignore(self.windows.remove(index))
      break
    }
  }
  @xlog.info(category="proton.window") <?
    { "message": "window closed", "window": running.id }
}

///|
fn RuntimeSession::all_windows_closed(self : RuntimeSession) -> Bool {
  self.has_created_window && self.windows.all(fn(window) { window.is_closed() })
}

///|
fn should_quit_after_last_window(
  policy : LastWindowClosedPolicy,
  has_windows : Bool,
  all_windows_closed : Bool,
) -> Bool {
  policy == LastWindowClosedPolicy::Quit && has_windows && all_windows_closed
}

///|
fn should_commit_application_close(
  decisions : Array[WindowCloseDecision],
) -> Bool {
  decisions.all(fn(decision) { decision == WindowCloseDecision::Allow })
}

///|
/// Whether an application quit step keeps the quit chain running.
fn should_continue_quit(decision : ApplicationQuitDecision) -> Bool {
  decision == ApplicationQuitDecision::Allow
}

///|
fn RuntimeSession::request_quit(self : RuntimeSession, exit_code : Int) -> Unit {
  let accepted = self.close_coordinator.begin_exit(Quit(exit_code))
  if accepted {
    self.wakeup.signal.notify()
  }
}

///|
fn RuntimeSession::request_update_install(
  self : RuntimeSession,
) -> Unit raise AppControlError {
  guard self.updates.channel is Some(_) else {
    raise NativeControlFailure(
      action="quit and install update",
      status=-1,
      detail="the application is stopping or has stopped",
    )
  }
  if self.close_coordinator.purpose == InstallUpdate {
    return
  }
  guard self.config.instance_identifier is None ||
    self.has_single_instance_lock() else {
    raise NativeControlFailure(
      action="quit and install update",
      status=-1,
      detail="single-instance ownership has already been released",
    )
  }
  guard self.updates.prepared is Some(_) else {
    raise NativeControlFailure(
      action="quit and install update",
      status=-1,
      detail="no downloaded update is ready",
    )
  }
  guard !self.close_coordinator.relaunch_scheduled && !self.is_quitting() else {
    raise NativeControlFailure(
      action="quit and install update",
      status=-1,
      detail="another exit or relaunch is already pending",
    )
  }
  if self.close_coordinator.begin_exit(InstallUpdate) {
    self.wakeup.signal.notify()
  }
}

///|
fn RuntimeSession::request_exit(self : RuntimeSession, exit_code : Int) -> Unit {
  if self.close_coordinator.begin_exit(ForceExit(exit_code)) {
    self.wakeup.signal.notify()
  }
}

///|
fn RuntimeSession::is_quitting(self : RuntimeSession) -> Bool {
  self.close_coordinator.is_quitting()
}

///|
/// Preserves the exit mode alongside the status through runtime cleanup.
fn RuntimeSession::resolved_exit(self : RuntimeSession) -> ApplicationExit {
  {
    exit_code: self.close_coordinator.exit_code(),
    forced: self.close_coordinator.is_forced(),
    update: None,
  }
}

///|
/// Reports whether this process still holds the single-instance lock it
/// acquired at startup.
fn RuntimeSession::has_single_instance_lock(self : RuntimeSession) -> Bool {
  self.app_instance is Some(_)
}

///|
/// Releases the single-instance lock so another launch can become primary.
/// The application keeps running without receiving further activations.
fn RuntimeSession::release_single_instance_lock(
  self : RuntimeSession,
) -> Unit raise AppControlError {
  guard self.app_instance is None ||
    self.close_coordinator.purpose != InstallUpdate else {
    raise NativeControlFailure(
      action="release the single-instance lock",
      status=-1,
      detail="update installation owns the pending exit",
    )
  }
  match self.app_instance {
    Some(instance) =>
      instance.release() catch {
        error =>
          raise app_control_native_error(
            "release the single-instance lock", error,
          )
      }
    None => ()
  }
  self.app_instance = None
}

///|
fn RuntimeSession::advance_application_lifetime(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  let mut did_work = false
  if self.close_coordinator.state == CloseRunning &&
    !self.close_coordinator.last_window_quit_handled &&
    should_quit_after_last_window(
      self.config.last_window_closed_policy,
      self.has_created_window,
      self.all_windows_closed(),
    ) {
    self.close_coordinator.last_window_quit_handled = true
    self.request_quit(0)
    did_work = true
  }
  if self.close_coordinator.is_forced() && self.advance_forced_exit() {
    did_work = true
  }
  match self.close_coordinator.state {
    CloseRunning =>
      if self.advance_individual_close_decisions() {
        did_work = true
      }
    CloseBeforeQuit => if self.advance_before_quit() { did_work = true }
    CloseQuitRequested => {
      self.begin_application_close_decisions()
      did_work = true
    }
    CloseCollecting =>
      if self.advance_application_close_decisions() {
        did_work = true
      }
    CloseClosingWindows =>
      if self.advance_close_completion() {
        did_work = true
      }
    CloseWillQuit => if self.advance_will_quit() { did_work = true }
    CloseQuitting => if self.advance_quit_event() { did_work = true }
    CloseCommitted => ()
  }
  did_work
}

///|
/// Escalates a quit request to Electron's `app.exit` behavior: windows are
/// destroyed without asking and the cancelable quit steps are skipped.
fn RuntimeSession::advance_forced_exit(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  match self.close_coordinator.state {
    CloseRunning
    | CloseBeforeQuit
    | CloseQuitRequested
    | CloseCollecting
    | CloseWillQuit => {
      self.begin_forced_close()
      true
    }
    // Window teardown is already in progress. The final notification is not
    // cancelable; a forced request there can only replace the exit code.
    CloseClosingWindows | CloseQuitting | CloseCommitted => false
  }
}

///|
fn RuntimeSession::advance_before_quit(self : RuntimeSession) -> Bool {
  match self.config.before_quit_handler {
    None => {
      self.close_coordinator.state = CloseQuitRequested
      return true
    }
    Some(handler) =>
      match self.advance_quit_decision(handler) {
        None => false
        Some(decision) => {
          if should_continue_quit(decision) {
            self.close_coordinator.state = CloseQuitRequested
          } else {
            self.close_coordinator.cancel_quit_transaction()
          }
          true
        }
      }
  }
}

///|
fn RuntimeSession::advance_will_quit(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  match self.config.will_quit_handler {
    None => {
      self.begin_quit_event()
      true
    }
    Some(handler) =>
      match self.advance_quit_decision(handler) {
        None => false
        Some(decision) => {
          if should_continue_quit(decision) {
            self.begin_quit_event()
          } else {
            self.close_coordinator.cancel_quit_transaction()
          }
          true
        }
      }
  }
}

///|
/// Spawns the cancelable handler of the current step once and reports its
/// decision as soon as the task has completed.
fn RuntimeSession::advance_quit_decision(
  self : RuntimeSession,
  handler : async (ApplicationContext) -> ApplicationQuitDecision noraise,
) -> ApplicationQuitDecision? {
  if self.close_coordinator.pending_quit is None {
    let context = self.application_context()
    self.close_coordinator.pending_quit = Some(
      self.application_tasks.spawn(
        () => {
          defer self.wakeup.signal.notify()
          handler(context)
        },
        no_wait=true,
      ),
    )
  }
  match self.close_coordinator.pending_quit {
    None => None
    Some(task) => {
      let completed = task.try_wait() catch {
        _ => Some(ApplicationQuitDecision::Allow)
      }
      match completed {
        None => None
        Some(decision) => {
          self.close_coordinator.pending_quit = None
          Some(decision)
        }
      }
    }
  }
}

///|
/// Runs the application notification of the last quit step and waits for it,
/// matching Electron's synchronous `quit` emission before shutdown.
fn RuntimeSession::begin_quit_event(
  self : RuntimeSession,
) -> Unit raise AppRunError {
  // The quit can no longer be cancelled from here on, so a later launch of the
  // same application must not start new windows.
  self.runtime.stop_app_activations() catch {
    error => raise native_run_error("stop app activations", error)
  }
  self.close_coordinator.state = CloseQuitting
  guard !self.config.quit_handlers.is_empty() else {
    self.close_coordinator.state = CloseCommitted
    return
  }
  let context = self.application_context()
  let handlers = self.config.quit_handlers
  let exit_code = self.close_coordinator.exit_code()
  self.close_coordinator.pending_quit = Some(
    self.application_tasks.spawn(
      () => {
        defer self.wakeup.signal.notify()
        for handler in handlers {
          handler(context, exit_code)
        }
        ApplicationQuitDecision::Allow
      },
      no_wait=true,
    ),
  )
}

///|
fn RuntimeSession::advance_quit_event(self : RuntimeSession) -> Bool {
  match self.close_coordinator.pending_quit {
    None => {
      self.close_coordinator.state = CloseCommitted
      true
    }
    Some(task) => {
      let completed = task.try_wait() catch {
        _ => Some(ApplicationQuitDecision::Allow)
      }
      match completed {
        None => false
        Some(_) => {
          self.close_coordinator.pending_quit = None
          self.close_coordinator.state = CloseCommitted
          true
        }
      }
    }
  }
}

///|
/// Returns a prevented quit request to the running state. Windows that were
/// already closed stay closed, and the automatic last-window quit is not
/// retried until a window is created again.
fn CloseCoordinator::cancel_quit_transaction(self : CloseCoordinator) -> Unit {
  self.pending_quit = None
  self.purpose = Quit(0)
  self.state = CloseRunning
}

///|
/// Destroys every window without asking, the native half of `app.exit`.
fn RuntimeSession::begin_forced_close(
  self : RuntimeSession,
) -> Unit raise AppRunError {
  self.close_coordinator.cancel_all()
  // A forced exit never returns to the running state, but keep the last-window
  // policy from requesting a second quit while these windows are destroyed.
  self.close_coordinator.last_window_quit_handled = true
  for running in self.windows {
    guard running.is_active() else { continue }
    running.window.destroy() catch {
      error => raise native_run_error("destroy window " + running.id, error)
    }
    running.state = WindowCloseRequested
  }
  self.close_coordinator.state = CloseClosingWindows
}

///|
/// Advances after the application-wide close step: the quit chain continues
/// once no window of this application is alive any more.
fn RuntimeSession::advance_close_completion(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  guard self.windows_fully_closed() else { return false }
  if self.close_coordinator.is_forced() {
    self.begin_quit_event()
  } else {
    self.close_coordinator.state = CloseWillQuit
  }
  true
}

///|
fn RuntimeSession::windows_fully_closed(self : RuntimeSession) -> Bool {
  self.windows.is_empty() &&
  self.window_commands.is_empty() &&
  self.pending_window_opens.is_empty()
}

///|
fn RuntimeSession::begin_application_close_decisions(
  self : RuntimeSession,
) -> Unit raise AppRunError {
  guard self.config.window_close_handler is Some(handler) else {
    self.commit_application_close()
    return
  }
  for running in self.windows {
    guard running.is_active() else { continue }
    let window_id = running.native_id
    guard self.close_coordinator.find(window_id) is None else { continue }
    let handle = self.window_handle(running)
    let task = self.window_tasks.spawn(
      () => {
        defer self.wakeup.signal.notify()
        handler(handle)
      },
      no_wait=true,
    )
    self.close_coordinator.pending.push(PendingCloseDecision::{
      window: window_id,
      task,
      decision: None,
      native_request: None,
    })
  }
  if self.close_coordinator.pending.is_empty() {
    self.commit_application_close()
  } else {
    self.close_coordinator.state = CloseCollecting
  }
}

///|
fn RuntimeSession::advance_application_close_decisions(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  let mut did_work = false
  let mut waiting = false
  let decisions : Array[WindowCloseDecision] = []
  for pending in self.close_coordinator.pending {
    if pending.decision is None {
      let completed = pending.task.try_wait() catch {
        _ => Some(WindowCloseDecision::Allow)
      }
      match completed {
        Some(decision) => {
          pending.decision = Some(decision)
          did_work = true
        }
        None => waiting = true
      }
    }
    match pending.decision {
      Some(decision) => decisions.push(decision)
      None => waiting = true
    }
  }
  if waiting {
    return did_work
  }
  if !should_commit_application_close(decisions) {
    for pending in self.close_coordinator.pending {
      guard pending.decision is Some(decision) else { continue }
      if pending.native_request is Some(_) {
        self.respond_close_decision(pending, decision)
      }
    }
    self.close_coordinator.pending.clear()
    self.close_coordinator.cancel_quit_transaction()
  } else {
    self.commit_application_close()
  }
  true
}

///|
fn RuntimeSession::respond_close_decision(
  self : RuntimeSession,
  pending : PendingCloseDecision,
  decision : WindowCloseDecision,
) -> Unit raise AppRunError {
  match self.find_window_by_native_id(pending.window) {
    Some(window) if !window.is_closed() => {
      match pending.native_request {
        Some(request_id) =>
          window.window.respond_close_request(
            request_id,
            decision == WindowCloseDecision::Allow,
          ) catch {
            error =>
              if !error.is_stale_window_request() {
                raise native_run_error("respond to window close request", error)
              }
          }
        None => ()
      }
      window.state = if decision == WindowCloseDecision::Allow {
        WindowCloseRequested
      } else {
        WindowOpen
      }
    }
    _ => ()
  }
  pending.native_request = None
}

///|
fn RuntimeSession::commit_application_close(
  self : RuntimeSession,
) -> Unit raise AppRunError {
  // Every window of this application is about to be closed. The last-window
  // policy must not request a second quit after a prevented `will-quit`.
  self.close_coordinator.last_window_quit_handled = true
  self.close_coordinator.state = CloseClosingWindows
  self.close_coordinator.pending.clear()
  for running in self.windows {
    guard running.is_active() else { continue }
    if self.config.window_close_handler is Some(_) {
      running.window.set_close_interception(false) catch {
        error =>
          raise native_run_error(
            "commit close interception for " + running.id,
            error,
          )
      }
    }
    running.window.close() catch {
      error => raise native_run_error("close window " + running.id, error)
    }
    running.state = WindowCloseRequested
  }
}

///|
fn RuntimeSession::quit_complete(self : RuntimeSession) -> Bool {
  self.close_coordinator.state == CloseCommitted &&
  self.windows.all(fn(window) { window.is_closed() }) &&
  self.window_commands.length() == 0 &&
  self.pending_window_opens.length() == 0 &&
  self.close_coordinator.pending.length() == 0
}

///|
fn RuntimeSession::cancel_all_bridge_tasks(self : RuntimeSession) -> Unit {
  runtime_session_cancel_all_bridge_tasks(self.pending_bridge)
}

///|
fn runtime_session_cancel_all_bridge_tasks(
  pending_bridge : Array[BridgeDispatchTask],
) -> Unit {
  for item in pending_bridge {
    if item.state == Running {
      item.task.cancel()
      item.state = Cancelled
    }
  }
  pending_bridge.clear()
}

///|
fn runtime_session_cancel_window_bridge_tasks(
  pending_bridge : Array[BridgeDispatchTask],
  window_id : Int64?,
) -> Unit {
  match window_id {
    Some(window_id) =>
      for item in pending_bridge {
        if item.window == window_id && item.state == Running {
          item.task.cancel()
          item.state = Cancelled
        }
      }
    None => ()
  }
}

///|
fn RuntimeSession::cancel_bridge_request(
  self : RuntimeSession,
  request_id : Int64?,
) -> Unit {
  runtime_session_cancel_bridge_request(self.pending_bridge, request_id)
}

///|
fn runtime_session_cancel_bridge_request(
  pending_bridge : Array[BridgeDispatchTask],
  request_id : Int64?,
) -> Unit {
  match request_id {
    Some(request_id) =>
      for item in pending_bridge {
        if item.request_id == request_id && item.state == Running {
          item.task.cancel()
          item.state = Cancelled
        }
      }
    None => ()
  }
}

///|
/// Names the CEF renderer termination status the way Electron names render
/// process gone reasons. CEF reports only unexpected terminations, so
/// Electron's `clean-exit` and `memory-eviction` never appear here.
fn render_process_gone_reason(status : Int) -> RenderProcessGoneReason {
  match status {
    0 => RenderProcessGoneReason::AbnormalExit
    1 => RenderProcessGoneReason::Killed
    2 => RenderProcessGoneReason::Crashed
    3 => RenderProcessGoneReason::OutOfMemory
    4 => RenderProcessGoneReason::LaunchFailed
    5 => RenderProcessGoneReason::IntegrityFailure
    _ => RenderProcessGoneReason::Unknown
  }
}

///|
/// Reports the session Proton created for this run, once, during startup.
fn RuntimeSession::emit_session_created(self : RuntimeSession) -> Unit {
  guard !self.config.session_created_handlers.is_empty() else { return }
  let session = self.environment.application_session
  for handler in self.config.session_created_handlers {
    ignore(self.application_tasks.spawn(() => handler(session), no_wait=true))
  }
}

///|
/// Reports one window creation to the application handlers.
fn RuntimeSession::emit_window_created(
  self : RuntimeSession,
  window : RunningWindow,
) -> Unit {
  guard !self.config.window_created_handlers.is_empty() else { return }
  let handle = self.window_handle(window)
  for handler in self.config.window_created_handlers {
    ignore(self.application_tasks.spawn(() => handler(handle), no_wait=true))
  }
}

///|
/// Reports one web contents creation to the application handlers.
fn RuntimeSession::emit_web_contents_created(
  self : RuntimeSession,
  contents : WebContentsHandle,
) -> Unit {
  guard !self.config.web_contents_created_handlers.is_empty() else { return }
  for handler in self.config.web_contents_created_handlers {
    ignore(self.application_tasks.spawn(() => handler(contents), no_wait=true))
  }
}

///|
/// Reports one renderer termination to the application handlers.
fn RuntimeSession::emit_render_process_gone(
  self : RuntimeSession,
  contents : WebContentsHandle,
  details : RenderProcessGoneDetails,
) -> Unit {
  guard !self.config.render_process_gone_handlers.is_empty() else { return }
  for handler in self.config.render_process_gone_handlers {
    ignore(
      self.application_tasks.spawn(
        () => handler(contents, details),
        no_wait=true,
      ),
    )
  }
}

///|
fn RuntimeSession::forward_menu_command(
  self : RuntimeSession,
  command_id : String,
  focused_window : Int64?,
) -> Unit raise AppRunError {
  let target = match focused_window {
    Some(window_id) => self.find_window_by_native_id(window_id)
    None => None
  }
  let target = match target {
    Some(window) => Some(window)
    None => self.windows.get(0)
  }
  match target {
    Some(window) if window.is_active() =>
      forward_menu_command(window.window, command_id, focused_window)
    _ => ()
  }
}

///|
/// Sets the macOS Overlay button position. None restores the system layout.
/// Other styles and platforms accept this as a no-op.
pub fn WindowHandle::set_window_button_position(
  self : WindowHandle,
  position : WindowButtonPosition?,
) -> Unit raise WindowSessionError {
  self.with_window("set window button position", window => {
    window.set_button_position(position.map(p => (p.x, p.y)))
  })
}

///|
/// Returns the custom macOS Overlay position, or None for the system layout
/// and platforms/styles without custom positioning.
pub fn WindowHandle::window_button_position(
  self : WindowHandle,
) -> WindowButtonPosition? raise WindowSessionError {
  let running = self.session.resolve_window(self.id, self.native_id)
  let position = running.window.button_position() catch {
    error => raise window_operation_failed("read window button position", error)
  }
  position.map(p => WindowButtonPosition::{ x: p.0, y: p.1, })
}

///|
/// Returns the child view's declaration id, or None for the main page.
pub fn WebContentsHandle::view_id(self : WebContentsHandle) -> String? {
  match self.target {
    PrimaryPage => None
    ChildView(id, _) => Some(id)
  }
}

///|
/// Returns the webpage hosted by this view.
pub fn ViewHandle::web_contents(self : ViewHandle) -> WebContentsHandle {
  {
    session: self.session,
    id: self.window_id,
    native_id: self.window_native_id,
    target: ChildView(self.id, self.native_id),
  }
}

///|
fn CloseCoordinator::is_forced(self : CloseCoordinator) -> Bool {
  self.purpose is ForceExit(_)
}

///|
fn CloseCoordinator::exit_code(self : CloseCoordinator) -> Int {
  match self.purpose {
    Quit(code) | ForceExit(code) => code
    InstallUpdate => 0
  }
}

///|
fn CloseCoordinator::accepts_download(self : CloseCoordinator) -> Bool {
  self.purpose != InstallUpdate &&
  self.state != CloseQuitting &&
  self.state != CloseCommitted &&
  !self.is_forced()
}
