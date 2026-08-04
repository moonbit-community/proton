///|
fn RuntimeSession::new(
  runtime : @native.Runtime,
  definitions : Array[PreparedWindow],
  windows : Array[RunningWindow],
  command_host : CommandHostRuntime?,
  wakeup : RuntimeWakeup,
  forward_menu_events : Bool,
  monitor_bridge : Bool,
  launch_input_handlers : Array[async (RuntimeLaunchInput) -> Unit noraise],
  window_event_handlers : Array[
    async (WindowHandle, WindowEvent) -> Unit noraise,
  ],
  window_tasks : @async.TaskGroup[Unit],
  window_close_handler : (async (WindowHandle) -> WindowCloseDecision noraise)?,
  window_lifecycle_hooks : Array[WindowLifecycleHook],
  lifecycle_failures : Array[AppCleanupError],
  bridge_startup_timeout_ms : Int,
  navigation_handler : (async (BrowserHandle, NavigationRequest) -> NavigationDecision noraise)?,
  popup_handler : (async (BrowserHandle, PopupRequest) -> PopupDecision noraise)?,
  download_handler : (async (BrowserHandle, DownloadRequest) -> DownloadDecision noraise)?,
  certificate_handler : (async (BrowserHandle, CertificateError) -> BrowserPermissionDecision noraise)?,
  media_handler : (async (BrowserHandle, MediaPermissionRequest) -> BrowserPermissionDecision noraise)?,
  download_event_handlers : Array[
    async (BrowserHandle, DownloadEvent) -> Unit noraise,
  ],
) -> RuntimeSession {
  RuntimeSession::{
    runtime,
    definitions,
    windows,
    command_host,
    pending_bridge: [],
    wakeup,
    forward_menu_events,
    monitor_bridge,
    launch_input_handlers,
    window_event_handlers,
    window_close_handler,
    window_tasks,
    window_lifecycle_hooks,
    lifecycle_failures,
    bridge_startup_timeout_ms,
    window_commands: [],
    pending_window_opens: [],
    pending_window_closes: [],
    pending_browser_requests: [],
    navigation_handler,
    popup_handler,
    download_handler,
    certificate_handler,
    media_handler,
    download_event_handlers,
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
fn RuntimeSession::window_handle(
  self : RuntimeSession,
  window : RunningWindow,
) -> WindowHandle {
  let id = window.id
  let native_id = window.window.id()
  WindowHandle::{
    id,
    native_id,
    show_window: () => {
      self.control_window(id, native_id, "show", window => window.show())
    },
    hide_window: () => {
      self.control_window(id, native_id, "hide", window => window.hide())
    },
    close_window: () => self.close_window(id, native_id),
    focus_window: () => {
      self.control_window(id, native_id, "focus", window => window.focus())
    },
    set_window_title: title => {
      self.control_window(id, native_id, "set title", window => {
        window.set_title(title)
      })
    },
    set_window_size: (width, height) => {
      self.control_window(id, native_id, "set size", window => {
        window.set_size(width, height)
      })
    },
    minimize_window: () => {
      self.control_window(id, native_id, "minimize", window => window.minimize())
    },
    maximize_window: () => {
      self.control_window(id, native_id, "maximize", window => window.maximize())
    },
    restore_window: () => {
      self.control_window(id, native_id, "restore", window => window.restore())
    },
    set_window_fullscreen: fullscreen => {
      self.control_window(id, native_id, "set fullscreen", window => {
        window.set_fullscreen(fullscreen)
      })
    },
    set_window_position: (x, y) => {
      self.control_window(id, native_id, "set position", window => {
        window.set_position(x, y)
      })
    },
    set_window_always_on_top: always_on_top => {
      self.control_window(id, native_id, "set always on top", window => {
        window.set_always_on_top(always_on_top)
      })
    },
    set_window_zoom_percent: zoom_percent => {
      self.control_window(id, native_id, "set zoom", window => {
        window.set_zoom_percent(zoom_percent)
      })
    },
    read_window_state: () => self.read_window_state(id, native_id),
    browser: self.browser_handle(window),
    add_view: (view_id, config) => {
      self.add_window_view(id, native_id, view_id, config)
    },
    remove_view: view_id => self.remove_window_view(id, native_id, view_id),
    list_views: () => self.list_window_views(id, native_id),
  }
}

///|
fn RuntimeSession::view_handle(
  self : RuntimeSession,
  window : RunningWindow,
  view : RunningView,
) -> ViewHandle {
  let window_id = window.id
  let window_native_id = window.window.id()
  let id = view.id
  let native_id = view.view.id()
  ViewHandle::{
    id,
    native_id,
    set_view_bounds: (x, y, width, height) => {
      self.control_view(
        window_id,
        window_native_id,
        id,
        native_id,
        "set bounds of",
        view => view.set_bounds(x, y, width, height),
      )
    },
    set_view_visible: visible => {
      self.control_view(
        window_id,
        window_native_id,
        id,
        native_id,
        "set visibility of",
        view => view.set_visible(visible),
      )
    },
    set_view_z_order: z_order => {
      self.control_view(
        window_id,
        window_native_id,
        id,
        native_id,
        "set z-order of",
        view => view.set_z_order(z_order),
      )
    },
    load_view_url: url => {
      self.control_view(
        window_id,
        window_native_id,
        id,
        native_id,
        "load URL in",
        view => view.load_url(url),
      )
    },
    read_view_state: () => {
      let running = self.resolve_view(
        window_id, window_native_id, id, native_id,
      )
      running.view.state() catch {
        error =>
          raise OperationFailed(
            action="read view " + id + " state in window " + window_id,
            error~,
          )
      }
    },
    close_view: () => self.remove_window_view(window_id, window_native_id, id),
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
  let running = match self.find_active_window(window_id) {
    Some(running) if running.window.id() == window_native_id => running
    _ => raise StaleWindow(id=window_id)
  }
  for view in running.views {
    if view.id == view_id {
      if view.view.id() != view_native_id {
        raise StaleView(id=view_id)
      }
      return view
    }
  }
  raise UnknownView(id=view_id)
}

///|
fn RuntimeSession::control_view(
  self : RuntimeSession,
  window_id : String,
  window_native_id : Int64,
  view_id : String,
  view_native_id : Int64,
  action : String,
  operation : (@native.View) -> Unit raise @native.NativeError,
) -> Unit raise WindowSessionError {
  let running = self.resolve_view(
    window_id, window_native_id, view_id, view_native_id,
  )
  operation(running.view) catch {
    error =>
      raise OperationFailed(
        action=action + " view " + view_id + " in window " + window_id,
        error~,
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
  let running = match self.find_active_window(window_id) {
    Some(running) if running.window.id() == window_native_id => running
    _ => raise StaleWindow(id=window_id)
  }
  if view_id.is_empty() {
    raise OperationFailed(
      action="add view to window " + window_id,
      error=@native.NativeError::InvalidArgument(
        message="view id must not be empty",
      ),
    )
  }
  for view in running.views {
    if view.id == view_id {
      raise AlreadyExists(id=view_id)
    }
  }
  let created = @native.View::new(running.window, config) catch {
    error =>
      raise OperationFailed(
        action="add view " + view_id + " to window " + window_id,
        error~,
      )
  }
  let running_view = RunningView::{ id: view_id, view: created }
  running.views.push(running_view)
  self.view_handle(running, running_view)
}

///|
fn RuntimeSession::remove_window_view(
  self : RuntimeSession,
  window_id : String,
  window_native_id : Int64,
  view_id : String,
) -> Unit raise WindowSessionError {
  let running = match self.find_active_window(window_id) {
    Some(running) if running.window.id() == window_native_id => running
    _ => raise StaleWindow(id=window_id)
  }
  let mut index = -1
  for i, view in running.views {
    if view.id == view_id {
      index = i
      break
    }
  }
  if index < 0 {
    raise UnknownView(id=view_id)
  }
  let view = running.views[index]
  view.view.destroy() catch {
    error =>
      raise OperationFailed(
        action="remove view " + view_id + " from window " + window_id,
        error~,
      )
  }
  ignore(running.views.remove(index))
}

///|
fn RuntimeSession::list_window_views(
  self : RuntimeSession,
  window_id : String,
  window_native_id : Int64,
) -> Array[ViewHandle] {
  match self.find_active_window(window_id) {
    Some(running) if running.window.id() == window_native_id =>
      running.views.map(view => self.view_handle(running, view))
    _ => []
  }
}

///|
fn RuntimeSession::browser_handle(
  self : RuntimeSession,
  window : RunningWindow,
) -> BrowserHandle {
  let id = window.id
  let native_id = window.window.id()
  BrowserHandle::{
    id,
    native_id,
    load_browser_url: url => {
      self.control_window(id, native_id, "load URL in", window => {
        window.load_url(url)
      })
    },
    load_browser_html: (html, base_url) => {
      self.control_window(id, native_id, "load HTML in", window => {
        window.load_html(html, base_url)
      })
    },
    eval_browser_script: script => {
      self.control_window(id, native_id, "evaluate script in", window => {
        window.eval(script)
      })
    },
    send_browser_command: (command, download_id) => {
      self.control_window(id, native_id, command + " in", window => {
        window.browser_command(command, download_id?)
      })
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
fn RuntimeSession::close_window(
  self : RuntimeSession,
  id : String,
  native_id : Int64,
) -> Unit raise WindowSessionError {
  let running = match self.find_active_window(id) {
    Some(running) if running.window.id() == native_id => running
    _ => raise StaleWindow(id~)
  }
  running.window.close() catch {
    error => raise OperationFailed(action="close window " + id, error~)
  }
  if self.window_close_handler is None {
    running.state = WindowCloseRequested
  }
}

///|
fn RuntimeSession::control_window(
  self : RuntimeSession,
  id : String,
  native_id : Int64,
  action : String,
  operation : (@native.Window) -> Unit raise @native.NativeError,
) -> Unit raise WindowSessionError {
  let running = match self.find_active_window(id) {
    Some(running) if running.window.id() == native_id => running
    _ => raise StaleWindow(id~)
  }
  operation(running.window) catch {
    error => raise OperationFailed(action=action + " window " + id, error~)
  }
}

///|
fn RuntimeSession::read_window_state(
  self : RuntimeSession,
  id : String,
  native_id : Int64,
) -> @native.WindowState raise WindowSessionError {
  let running = match self.find_active_window(id) {
    Some(running) if running.window.id() == native_id => running
    _ => raise StaleWindow(id~)
  }
  running.window.state() catch {
    error =>
      raise OperationFailed(action="read window " + id + " state", error~)
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
  let created_window = @native.Window::new(
    self.runtime,
    config=native_window_config(
      plan.window,
      definition.bridge,
      definition.browser_policy,
    ),
  ) catch {
    error => raise native_run_error("create window " + plan.id, error)
  }
  if self.window_close_handler is Some(_) {
    created_window.set_close_interception(true) catch {
      error =>
        raise native_run_error(
          "enable close interception for " + plan.id,
          error,
        )
    }
  }
  let running = RunningWindow::{
    id: plan.id,
    window: created_window,
    permissions: definition.permissions,
    lifetime: WindowLifetime::new(),
    views: [],
    bridge_ready: !self.monitor_bridge,
    state: WindowStarting,
  }
  self.windows.push(running)
  load_entry_after_create(created_window, plan.entry) catch {
    error => raise EntryLoadError(error)
  }
  running
}

///|
async fn RuntimeSession::activate_window(
  self : RuntimeSession,
  running : RunningWindow,
) -> Unit raise AppRunError {
  if running.lifetime.ready {
    running.lifetime.wait_until_ready()
    return
  }
  let window_events = WindowEventEmitter::new(
    typed_event_sender(running.window, None),
  )
  let manager = self.window_manager()
  let handle = self.window_handle(running)
  ignore(
    self.window_tasks.spawn(
      () => {
        run_window_lifecycle_scope(
          running,
          handle,
          manager,
          window_events,
          self.window_lifecycle_hooks,
          self.lifecycle_failures,
        )
      },
      no_wait=true,
      allow_failure=true,
    ),
  )
  running.lifetime.wait_until_ready()
  if running.is_closed() {
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
) -> WindowHandle raise WindowSessionError {
  let completion = WindowOpenCompletion::new()
  self.window_commands.push(Open(id, completion))
  self.wakeup.signal.notify()
  completion.wait()
}

///|
fn WindowOpenCompletion::new() -> WindowOpenCompletion {
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
) -> WindowHandle raise WindowSessionError {
  while self.state is WindowOpenPending {
    self.changed.wait() catch {
      _ => raise Cancelled
    }
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
        @async.sleep(self.bridge_startup_timeout_ms) catch {
          _ => ()
        }
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
fn RuntimeSession::advance_window_opens(self : RuntimeSession) -> Bool {
  let remaining : Array[PendingWindowOpen] = []
  let mut did_work = false
  for pending in self.pending_window_opens {
    let timed_out = pending.timeout.try_wait() catch { _ => Some(()) }
    if timed_out is Some(_) {
      did_work = true
      let state = Some(pending.running.window.bridge_lifecycle_state()) catch {
        _ => None
      }
      let error = match state {
        Some(state) =>
          BridgeStartupError(
            bridge_startup_timeout_diagnostic(
              state,
              self.bridge_startup_timeout_ms,
            ),
          )
        None =>
          NativeRuntimeError(
            action="open window " + pending.id,
            error=@native.NativeError::InvalidPayload(
              context="bridge startup",
              message="window startup timed out",
            ),
          )
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
            if pending.running.is_closed() {
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
fn RuntimeSession::fail_window_open(
  _self : RuntimeSession,
  pending : PendingWindowOpen,
  error : AppRunError,
) -> Unit {
  pending.timeout.cancel()
  match pending.activation {
    Some(task) => task.cancel()
    None => ()
  }
  pending.running.window.destroy() catch {
    _ => ()
  }
  pending.running.state = WindowClosed
  pending.running.lifetime.close()
  pending.completion.fail(StartupFailed(id=pending.id, error~))
}

///|
/// Opens one declared window that is not currently active.
pub async fn WindowManager::open(
  self : WindowManager,
  id : String,
) -> WindowHandle raise WindowSessionError {
  (self.open_window)(id)
}

///|
/// Returns the active instance for a declared window id.
pub fn WindowManager::find(self : WindowManager, id : String) -> WindowHandle? {
  (self.find_window)(id)
}

///|
/// Returns the declarative id of this window.
pub fn WindowHandle::id(self : WindowHandle) -> String {
  self.id
}

///|
/// Returns a low-level non-owning reference for APIs such as dialogs.
pub fn WindowHandle::as_native_ref(self : WindowHandle) -> @native.WindowRef {
  @native.WindowRef::unsafe_from_handle(self.native_id)
}

///|
pub fn WindowHandle::show(self : WindowHandle) -> Unit raise WindowSessionError {
  (self.show_window)()
}

///|
pub fn WindowHandle::hide(self : WindowHandle) -> Unit raise WindowSessionError {
  (self.hide_window)()
}

///|
pub fn WindowHandle::close(
  self : WindowHandle,
) -> Unit raise WindowSessionError {
  (self.close_window)()
}

///|
pub fn WindowHandle::focus(
  self : WindowHandle,
) -> Unit raise WindowSessionError {
  (self.focus_window)()
}

///|
pub fn WindowHandle::set_title(
  self : WindowHandle,
  title : String,
) -> Unit raise WindowSessionError {
  (self.set_window_title)(title)
}

///|
pub fn WindowHandle::set_size(
  self : WindowHandle,
  width : Int,
  height : Int,
) -> Unit raise WindowSessionError {
  (self.set_window_size)(width, height)
}

///|
pub fn WindowHandle::minimize(
  self : WindowHandle,
) -> Unit raise WindowSessionError {
  (self.minimize_window)()
}

///|
pub fn WindowHandle::maximize(
  self : WindowHandle,
) -> Unit raise WindowSessionError {
  (self.maximize_window)()
}

///|
pub fn WindowHandle::restore(
  self : WindowHandle,
) -> Unit raise WindowSessionError {
  (self.restore_window)()
}

///|
pub fn WindowHandle::set_fullscreen(
  self : WindowHandle,
  fullscreen : Bool,
) -> Unit raise WindowSessionError {
  (self.set_window_fullscreen)(fullscreen)
}

///|
pub fn WindowHandle::set_position(
  self : WindowHandle,
  x : Int,
  y : Int,
) -> Unit raise WindowSessionError {
  (self.set_window_position)(x, y)
}

///|
pub fn WindowHandle::set_always_on_top(
  self : WindowHandle,
  always_on_top : Bool,
) -> Unit raise WindowSessionError {
  (self.set_window_always_on_top)(always_on_top)
}

///|
pub fn WindowHandle::set_zoom_percent(
  self : WindowHandle,
  zoom_percent : Int,
) -> Unit raise WindowSessionError {
  (self.set_window_zoom_percent)(zoom_percent)
}

///|
pub fn WindowHandle::state(
  self : WindowHandle,
) -> @native.WindowState raise WindowSessionError {
  (self.read_window_state)()
}

///|
pub fn WindowHandle::browser(self : WindowHandle) -> BrowserHandle {
  self.browser
}

///|
/// Adds a web contents view to this window, following the Electron
/// `WebContentsView` model: the view renders its own page above the window's
/// main browser content at explicit bounds. `id` is unique within the window
/// and lets the session reject stale handles.
pub fn WindowHandle::add_view(
  self : WindowHandle,
  id : String,
  config : @native.ViewConfig,
) -> ViewHandle raise WindowSessionError {
  (self.add_view)(id, config)
}

///|
/// Removes and destroys a web contents view previously added with `add_view`.
pub fn WindowHandle::remove_view(
  self : WindowHandle,
  id : String,
) -> Unit raise WindowSessionError {
  (self.remove_view)(id)
}

///|
/// Lists the live web contents views of this window.
pub fn WindowHandle::views(self : WindowHandle) -> Array[ViewHandle] {
  (self.list_views)()
}

///|
/// Returns the declarative id of this view.
pub fn ViewHandle::id(self : ViewHandle) -> String {
  self.id
}

///|
/// Returns a low-level non-owning reference for native APIs.
pub fn ViewHandle::as_native_ref(self : ViewHandle) -> @native.ViewRef {
  @native.ViewRef::unsafe_from_handle(self.native_id)
}

///|
/// Moves and resizes the view. `x`/`y` use a top-left origin in the owning
/// window's content coordinate space, matching Electron's `setBounds`.
pub fn ViewHandle::set_bounds(
  self : ViewHandle,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Unit raise WindowSessionError {
  (self.set_view_bounds)(x, y, width, height)
}

///|
pub fn ViewHandle::set_visible(
  self : ViewHandle,
  visible : Bool,
) -> Unit raise WindowSessionError {
  (self.set_view_visible)(visible)
}

///|
/// Stacks the view relative to the window's other views; higher `z_order`
/// renders above lower values.
pub fn ViewHandle::set_z_order(
  self : ViewHandle,
  z_order : Int,
) -> Unit raise WindowSessionError {
  (self.set_view_z_order)(z_order)
}

///|
/// Navigates the view's page, the Electron `view.webContents.loadURL`
/// equivalent.
pub fn ViewHandle::load_url(
  self : ViewHandle,
  url : String,
) -> Unit raise WindowSessionError {
  (self.load_view_url)(url)
}

///|
/// Reads the current view state from the native runtime.
pub fn ViewHandle::state(
  self : ViewHandle,
) -> @native.ViewState raise WindowSessionError {
  (self.read_view_state)()
}

///|
/// Removes and destroys the view, the Electron `removeChildView` equivalent.
pub fn ViewHandle::close(self : ViewHandle) -> Unit raise WindowSessionError {
  (self.close_view)()
}

///|
pub fn BrowserHandle::window_id(self : BrowserHandle) -> String {
  self.id
}

///|
pub fn BrowserHandle::load_url(
  self : BrowserHandle,
  url : String,
) -> Unit raise WindowSessionError {
  (self.load_browser_url)(url)
}

///|
pub fn BrowserHandle::load_html(
  self : BrowserHandle,
  html : String,
  base_url : String,
) -> Unit raise WindowSessionError {
  (self.load_browser_html)(html, base_url)
}

///|
pub fn BrowserHandle::eval(
  self : BrowserHandle,
  script : String,
) -> Unit raise WindowSessionError {
  (self.eval_browser_script)(script)
}

///|
pub fn BrowserHandle::back(
  self : BrowserHandle,
) -> Unit raise WindowSessionError {
  (self.send_browser_command)("back", None)
}

///|
pub fn BrowserHandle::forward(
  self : BrowserHandle,
) -> Unit raise WindowSessionError {
  (self.send_browser_command)("forward", None)
}

///|
pub fn BrowserHandle::reload(
  self : BrowserHandle,
  ignore_cache? : Bool = false,
) -> Unit raise WindowSessionError {
  (self.send_browser_command)(
    if ignore_cache {
      "reload_ignore_cache"
    } else {
      "reload"
    },
    None,
  )
}

///|
pub fn BrowserHandle::stop(
  self : BrowserHandle,
) -> Unit raise WindowSessionError {
  (self.send_browser_command)("stop", None)
}

///|
pub fn BrowserHandle::open_devtools(
  self : BrowserHandle,
) -> Unit raise WindowSessionError {
  (self.send_browser_command)("open_devtools", None)
}

///|
pub fn BrowserHandle::close_devtools(
  self : BrowserHandle,
) -> Unit raise WindowSessionError {
  (self.send_browser_command)("close_devtools", None)
}

///|
pub fn BrowserHandle::cancel_download(
  self : BrowserHandle,
  download_id : Int,
) -> Unit raise WindowSessionError {
  (self.send_browser_command)("cancel_download", Some(download_id))
}

///|
fn RuntimeSession::command_host(self : RuntimeSession) -> @core.AppCommandHost? {
  self.command_host.map(host => host.host)
}

///|
async fn RuntimeSession::wait_for_bridge_startup(
  self : RuntimeSession,
  timeout_ms : Int,
) -> Unit raise AppRunError {
  let completed = @async.with_timeout_opt(timeout_ms, () => {
    while true {
      let revision = self.wakeup.revision()
      let did_work = self.pump_once(monitor_bridge=false)
      match refresh_bridge_startup_states(self.windows) {
        None => return
        Some(_) =>
          if did_work {
            @async.sleep(0)
          } else {
            self.wakeup.wait_after(revision)
          }
      }
    }
  }) catch {
    error => raise normalize_async_run_error(error)
  }
  match completed {
    Some(_) => ()
    None => {
      ignore(self.pump_once(monitor_bridge=false))
      match refresh_bridge_startup_states(self.windows) {
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
async fn RuntimeSession::run(self : RuntimeSession) -> Unit raise AppRunError {
  while !self.all_windows_closed() ||
        self.window_commands.length() > 0 ||
        self.pending_window_opens.length() > 0 {
    let revision = self.wakeup.revision()
    let did_work = self.pump_once(monitor_bridge=self.monitor_bridge)
    if did_work {
      @async.sleep(0) catch {
        error => raise normalize_async_run_error(error)
      }
    } else {
      self.wakeup.wait_after(revision)
    }
  }
  self.cancel_all_bridge_tasks()
  self.cancel_all_window_close_requests()
  self.cancel_all_browser_requests()
}

///|
async fn RuntimeSession::drive_until_complete(
  self : RuntimeSession,
  task : @async.Task[Unit],
) -> Unit raise AppRunError {
  while true {
    let revision = self.wakeup.revision()
    let completed = task.try_wait() catch {
      error => raise normalize_async_run_error(error)
    }
    match completed {
      Some(_) => return
      None => {
        let did_work = self.pump_once(monitor_bridge=self.monitor_bridge)
        if did_work {
          @async.sleep(0) catch {
            error => raise normalize_async_run_error(error)
          }
        } else {
          self.wakeup.wait_after(revision)
        }
      }
    }
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
  if monitor_bridge {
    self.check_bridge_failures()
  }
  if self.drain_bridge_requests() {
    did_work = true
  }
  if self.complete_bridge_requests() {
    did_work = true
  }
  if self.advance_window_opens() {
    did_work = true
  }
  if self.complete_window_close_requests() {
    did_work = true
  }
  if self.complete_browser_requests() {
    did_work = true
  }
  did_work
}

///|
fn RuntimeSession::drain_runtime_events(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  let mut did_work = false
  let mut polling = true
  while polling {
    let event = self.runtime.poll_event() catch {
      error => raise native_run_error("poll event", error)
    }
    match event {
      None => polling = false
      Some(event) => {
        did_work = true
        self.dispatch_runtime_event(event)
      }
    }
  }
  did_work
}

///|
fn RuntimeSession::dispatch_runtime_event(
  self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit raise AppRunError {
  self.dispatch_window_event(event)
  self.dispatch_browser_event(event)
  self.dispatch_notification_event(event)
  self.dispatch_launch_input_event(event)
  self.dispatch_menu_event(event)
  self.cancel_bridge_request(event.bridge_request_cancellation())
}

///|
fn RuntimeSession::dispatch_window_event(
  self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit {
  runtime_session_dispatch_window_event(
    self.windows,
    self.pending_bridge,
    event,
  )
  if event.is_window_closed() {
    self.cancel_window_close_requests(event.window_id())
    self.cancel_browser_requests(event.window_id())
  }
  match (event.window_id(), event.window_state_change()) {
    (Some(window_id), Some(state)) =>
      match self.find_window_by_native_id(window_id) {
        Some(window) => {
          let handle = self.window_handle(window)
          for handler in self.window_event_handlers {
            ignore(
              self.window_tasks.spawn(
                () => handler(handle, StateChanged(state)),
                no_wait=true,
              ),
            )
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
fn RuntimeSession::dispatch_browser_event(
  self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit {
  match event.browser_request() {
    Some(request) => self.start_browser_request(event.window_id(), request)
    None => ()
  }
  match (event.window_id(), event.browser_download_update()) {
    (Some(window_id), Some(update)) =>
      match self.find_window_by_native_id(window_id) {
        Some(window) => {
          let browser = self.browser_handle(window)
          let observed = DownloadEvent::{
            id: update.download_id,
            state: update.state,
            received_bytes: update.received_bytes,
            total_bytes: update.total_bytes,
            percent: update.percent,
          }
          for handler in self.download_event_handlers {
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
  request : @native.NativeBrowserRequest,
) -> Unit {
  guard window_id is Some(window_id) else { return }
  guard self.find_window_by_native_id(window_id) is Some(window) else { return }
  let browser = self.browser_handle(window)
  let request_id = match request {
    Navigation(request_id~, ..)
    | Popup(request_id~, ..)
    | Download(request_id~, ..)
    | Certificate(request_id~, ..)
    | Media(request_id~, ..) => request_id
  }
  let task = self.window_tasks.spawn(
    () => {
      defer self.wakeup.signal.notify()
      match request {
        Navigation(url~, http_method~, user_gesture~, redirect~, ..) =>
          match self.navigation_handler {
            Some(handler) =>
              match
                handler(browser, { url, http_method, user_gesture, redirect }) {
                NavigationDecision::Allow =>
                  BrowserResponse::{ action: "allow", path: None }
                NavigationDecision::Deny =>
                  BrowserResponse::{ action: "deny", path: None }
              }
            None => BrowserResponse::{ action: "deny", path: None }
          }
        Popup(url~, disposition~, user_gesture~, ..) => {
          let decision = match self.popup_handler {
            Some(handler) =>
              handler(browser, { url, disposition, user_gesture })
            None => PopupDecision::Deny
          }
          match decision {
            PopupDecision::Deny => ()
            PopupDecision::OpenInCurrent =>
              browser.load_url(url) catch {
                _ => ()
              }
            PopupDecision::OpenInWindow(id) => {
              let opened = Some(self.window_manager().open(id)) catch {
                _ => None
              }
              match opened {
                Some(window) => window.browser().load_url(url) catch { _ => () }
                None => ()
              }
            }
          }
          BrowserResponse::{ action: "deny", path: None }
        }
        Download(download_id~, url~, suggested_name~, ..) =>
          match self.download_handler {
            Some(handler) =>
              match handler(browser, { id: download_id, url, suggested_name }) {
                DownloadDecision::Deny =>
                  BrowserResponse::{ action: "deny", path: None }
                DownloadDecision::ShowSaveDialog =>
                  BrowserResponse::{ action: "allow", path: None }
                DownloadDecision::SaveTo(path) =>
                  BrowserResponse::{ action: "allow", path: Some(path) }
              }
            None => BrowserResponse::{ action: "deny", path: None }
          }
        Certificate(url~, error_code~, ..) =>
          match self.certificate_handler {
            Some(handler) =>
              match handler(browser, { url, error_code }) {
                BrowserPermissionDecision::Allow =>
                  BrowserResponse::{ action: "allow", path: None }
                BrowserPermissionDecision::Deny =>
                  BrowserResponse::{ action: "deny", path: None }
              }
            None => BrowserResponse::{ action: "deny", path: None }
          }
        Media(origin~, permissions~, ..) =>
          match self.media_handler {
            Some(handler) =>
              match handler(browser, { origin, permissions }) {
                BrowserPermissionDecision::Allow =>
                  BrowserResponse::{ action: "allow", path: None }
                BrowserPermissionDecision::Deny =>
                  BrowserResponse::{ action: "deny", path: None }
              }
            None => BrowserResponse::{ action: "deny", path: None }
          }
      }
    },
    no_wait=true,
  )
  self.pending_browser_requests.push({ window: window_id, request_id, task })
}

///|
fn RuntimeSession::complete_browser_requests(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  let remaining : Array[PendingBrowserRequest] = []
  let mut did_work = false
  for pending in self.pending_browser_requests {
    let completed = pending.task.try_wait() catch {
      _ => Some(BrowserResponse::{ action: "deny", path: None })
    }
    match completed {
      None => remaining.push(pending)
      Some(response) => {
        did_work = true
        match self.find_window_by_native_id(pending.window) {
          Some(window) if !window.is_closed() => {
            let path = response.path
            window.window.respond_browser_request(
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
fn RuntimeSession::cancel_all_browser_requests(self : RuntimeSession) -> Unit {
  for pending in self.pending_browser_requests {
    pending.task.cancel()
  }
  self.pending_browser_requests.clear()
}

///|
fn RuntimeSession::start_window_close_request(
  self : RuntimeSession,
  window_id : Int64,
  request_id : Int64,
) -> Unit {
  guard self.window_close_handler is Some(handler) else { return }
  guard self.find_window_by_native_id(window_id) is Some(window) else { return }
  let handle = self.window_handle(window)
  let task = self.window_tasks.spawn(
    () => {
      defer self.wakeup.signal.notify()
      handler(handle)
    },
    no_wait=true,
  )
  self.pending_window_closes.push(PendingWindowClose::{
    window: window_id,
    request_id,
    task,
  })
}

///|
fn RuntimeSession::complete_window_close_requests(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  let remaining : Array[PendingWindowClose] = []
  let mut did_work = false
  for pending in self.pending_window_closes {
    let completed = pending.task.try_wait() catch { _ => Some(Allow) }
    match completed {
      None => remaining.push(pending)
      Some(decision) => {
        did_work = true
        match self.find_window_by_native_id(pending.window) {
          Some(window) if !window.is_closed() => {
            window.window.respond_close_request(
              pending.request_id,
              decision == Allow,
            ) catch {
              error =>
                if !error.is_stale_window_request() {
                  raise native_run_error(
                    "respond to window close request", error,
                  )
                }
            }
            if decision == Allow {
              window.state = WindowCloseRequested
            }
          }
          _ => ()
        }
      }
    }
  }
  self.pending_window_closes.clear()
  for pending in remaining {
    self.pending_window_closes.push(pending)
  }
  did_work
}

///|
fn RuntimeSession::cancel_window_close_requests(
  self : RuntimeSession,
  window_id : Int64?,
) -> Unit {
  let remaining : Array[PendingWindowClose] = []
  for pending in self.pending_window_closes {
    if window_id == Some(pending.window) {
      pending.task.cancel()
    } else {
      remaining.push(pending)
    }
  }
  self.pending_window_closes.clear()
  for pending in remaining {
    self.pending_window_closes.push(pending)
  }
}

///|
fn RuntimeSession::cancel_all_window_close_requests(
  self : RuntimeSession,
) -> Unit {
  for pending in self.pending_window_closes {
    pending.task.cancel()
  }
  self.pending_window_closes.clear()
}

///|
fn runtime_session_dispatch_window_event(
  windows : Array[RunningWindow],
  pending_bridge : Array[BridgeDispatchTask],
  event : @native.RuntimeEvent,
) -> Unit {
  if event.is_window_closed() {
    runtime_session_mark_window_closed(windows, event.window_id())
    runtime_session_cancel_window_bridge_tasks(
      pending_bridge,
      event.window_id(),
    )
  }
}

///|
fn RuntimeSession::dispatch_notification_event(
  _self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit {
  match event.notification_result() {
    Some(result) => publish_notification_result(result)
    None => ()
  }
}

///|
fn RuntimeSession::dispatch_launch_input_event(
  self : RuntimeSession,
  event : @native.RuntimeEvent,
) -> Unit raise AppRunError {
  match event.launch_input() {
    Some(input) => {
      self.activate_for_launch_input()
      for handler in self.launch_input_handlers {
        ignore(self.window_tasks.spawn(() => handler(input), no_wait=true))
      }
    }
    None => ()
  }
}

///|
fn RuntimeSession::activate_for_launch_input(
  self : RuntimeSession,
) -> Unit raise AppRunError {
  let mut target : RunningWindow? = None
  for running in self.windows {
    if !running.is_closed() && running.id == "main" {
      target = Some(running)
      break
    }
  }
  if target is None {
    for running in self.windows {
      if !running.is_closed() {
        target = Some(running)
        break
      }
    }
  }
  match target {
    Some(running) => {
      let state = running.window.state() catch {
        error => raise native_run_error("read activation window state", error)
      }
      if state.minimized {
        running.window.restore() catch {
          error => raise native_run_error("restore activation window", error)
        }
      }
      if !state.visible {
        running.window.show() catch {
          error => raise native_run_error("show activation window", error)
        }
      }
      running.window.focus() catch {
        error => raise native_run_error("focus activation window", error)
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
fn RuntimeSession::check_bridge_failures(
  self : RuntimeSession,
) -> Unit raise AppRunError {
  for running in self.windows {
    if running.is_closed() {
      continue
    }
    let failure = take_runtime_bridge_failure(running.window) catch {
      error =>
        raise native_run_error("read bridge failure for " + running.id, error)
    }
    match failure {
      Some(diagnostic) => raise BridgeRuntimeError(diagnostic)
      None => ()
    }
  }
}

///|
fn RuntimeSession::drain_bridge_requests(
  self : RuntimeSession,
) -> Bool raise AppRunError {
  let mut did_work = false
  let mut polling = true
  while polling {
    let request = self.runtime.poll_bridge_request() catch {
      error => raise native_run_error("poll bridge request", error)
    }
    match request {
      None => polling = false
      Some(request) => {
        did_work = true
        self.start_bridge_request(request)
      }
    }
  }
  did_work
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
            target.window,
            target.id,
            target.permissions,
            host,
            request,
            self.wakeup.signal,
          )
        },
        no_wait=true,
        allow_failure=true,
      )
      self.pending_bridge.push(BridgeDispatchTask::{
        request_id,
        window: target.window.id(),
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
    if running.window.id() == window_id {
      return Some(running)
    }
  }
  None
}

///|
fn runtime_session_mark_window_closed(
  windows : Array[RunningWindow],
  window_id : Int64?,
) -> Unit {
  match window_id {
    Some(window_id) =>
      match runtime_session_find_window_by_native_id(windows, window_id) {
        Some(window) => {
          window.state = WindowClosed
          window.lifetime.close()
        }
        None => ()
      }
    None => ()
  }
}

///|
fn runtime_session_find_window_by_native_id(
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
fn RuntimeSession::all_windows_closed(self : RuntimeSession) -> Bool {
  self.windows.length() > 0 &&
  self.windows.all(fn(window) { window.is_closed() })
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
