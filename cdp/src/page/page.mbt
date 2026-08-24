///|
/// A page-scoped CDP session that owns main-frame execution-context state.
pub struct Page {
  priv client : @client.CdpClient
  priv state : PageState
  priv event_handler : Int
  priv close_handler : Int
}

///|
/// A navigation whose next main-frame context has not necessarily appeared yet.
pub struct Navigation {
  priv page : Page
  priv previous_generation : UInt64
}

///|
/// An explicitly created isolated JavaScript world.
pub struct IsolatedWorld {
  priv page : Page
  priv context_id : Int
}

///|
pub(all) suberror PageLifecycleError {
  Closed
  ContextLost
} derive(Debug)

///|
pub extend PageLifecycleError with Debug::{to_repr}

///|
pub(all) suberror JavaScriptError {
  Exception(Json)
  MissingValue(Json)
} derive(Debug)

///|
pub extend JavaScriptError with Debug::{to_repr}

///|
priv struct ExecutionContextLease {
  unique_id : String
  generation : UInt64
}

///|
priv struct PageState {
  mut main_frame_id : String?
  mut context : ExecutionContextLease?
  mut generation : UInt64
  mut closed : Bool
  changed : @async.CondVar
}

///|
fn PageState::new() -> PageState {
  {
    main_frame_id: None,
    context: None,
    generation: 0UL,
    closed: false,
    changed: @async.CondVar::Cond(),
  }
}

///|
/// Connects to a direct page target and enables page/context lifecycle events.
pub async fn[X] Page::connect(
  tasks : @async.TaskGroup[X],
  target : @client.CdpTarget,
  target_id? : String,
  url? : String,
  title? : String,
  timeout_ms? : Int = 25000,
) -> Page {
  let client = @client.connect_cdp_page_target_with_timeout(
    tasks,
    target,
    target_id?,
    url?,
    title?,
    timeout_ms~,
  )
  Page::initialize_scoped(tasks, client, timeout_ms)
}

///|
/// Connects to a direct page WebSocket and enables page/context lifecycle events.
pub async fn[X] Page::connect_web_socket(
  tasks : @async.TaskGroup[X],
  web_socket_url : String,
  timeout_ms? : Int = 25000,
) -> Page {
  let client = @client.CdpClient::connect_with_timeout(
    tasks,
    web_socket_url,
    timeout_ms~,
  )
  Page::initialize_scoped(tasks, client, timeout_ms)
}

///|
async fn[X] Page::initialize_scoped(
  tasks : @async.TaskGroup[X],
  client : @client.CdpClient,
  timeout_ms : Int,
) -> Page {
  errdefer client.close()
  let page = Page::initialize(client, timeout_ms)
  tasks.add_defer(() => page.close())
  page
}

///|
async fn Page::initialize(client : @client.CdpClient, timeout_ms : Int) -> Page {
  let state = PageState::new()
  let event_handler = client.on_cdp_event(event => state.handle_event(event))
  let close_handler = client.on_close(() => state.close())
  let page = Page::{ client, state, event_handler, close_handler }
  ignore(
    @client.cdp_response_result_json(
      client.send_schema_command("Page.enable", timeout_ms~),
    ),
  )
  let frame_tree = @client.cdp_response_result_json(
    client.send_schema_command("Page.getFrameTree", timeout_ms~),
  )
  guard frame_tree
    is { "frameTree": { "frame": { "id": String(main_frame_id), .. }, .. }, .. } else {
    raise @client.BrowserError::InvalidField("frameTree.frame.id")
  }
  state.set_main_frame(main_frame_id)
  ignore(
    @client.cdp_response_result_json(
      client.send_schema_command("Runtime.enable", timeout_ms~),
    ),
  )
  page
}

///|
/// Closes the page connection and wakes all lifecycle waiters.
pub async fn Page::close(self : Page) -> Unit {
  ignore(self.client.remove_cdp_event_handler(self.event_handler))
  ignore(self.client.remove_close_handler(self.close_handler))
  self.state.close()
  self.client.close()
}

///|
/// Evaluates JavaScript once in the current main-frame default context.
///
/// This operation never retries because the expression may have side effects.
pub async fn Page::evaluate(
  self : Page,
  expression : String,
  await_promise? : Bool = false,
) -> Json {
  let lease = self.state.wait_for_context()
  let response = self.client.send_schema_command("Runtime.evaluate", params={
    "expression": expression,
    "uniqueContextId": lease.unique_id,
    "returnByValue": true,
    "awaitPromise": await_promise,
  })
  self.evaluation_value(response, Some(lease))
}

///|
/// Evaluates a side-effect-free predicate until it becomes true.
///
/// Context replacement caused by navigation is expected and is the only CDP
/// command failure retried by this operation. Apply timeouts at the call site.
pub async fn Page::wait_until(self : Page, predicate : String) -> Unit {
  for ;; {
    let ready = self.evaluate(predicate) catch {
      PageLifecycleError::ContextLost => continue
      error => raise error
    }
    if ready is True {
      return
    }
    @async.sleep(100)
  }
}

///|
/// Starts a main-frame navigation.
pub async fn Page::navigate(self : Page, url : String) -> Navigation {
  let previous_generation = self.state.generation
  ignore(
    @client.cdp_response_result_json(
      self.client.send_schema_command("Page.navigate", params={ "url": url }),
    ),
  )
  { page: self, previous_generation }
}

///|
/// Reloads the page.
pub async fn Page::reload(self : Page) -> Navigation {
  let previous_generation = self.state.generation
  ignore(
    @client.cdp_response_result_json(
      self.client.send_schema_command("Page.reload"),
    ),
  )
  { page: self, previous_generation }
}

///|
/// Waits until navigation installs a newer main-frame execution context.
pub async fn Navigation::wait_for_context(self : Navigation) -> Unit {
  self.page.state.wait_for_generation_after(self.previous_generation)
}

///|
/// Captures a PNG screenshot and returns its base64 payload.
pub async fn Page::capture_png(self : Page) -> String {
  let result = @client.cdp_response_result_json(
    self.client.send_schema_command("Page.captureScreenshot", params={
      "format": "png",
      "fromSurface": true,
    }),
  )
  match result {
    { "data": String(data), .. } => data
    _ => raise @client.BrowserError::InvalidField("data")
  }
}

///|
/// Creates an isolated world for the main frame.
pub async fn Page::create_isolated_world(
  self : Page,
  world_name : String,
  grant_universal_access? : Bool = false,
) -> IsolatedWorld {
  let frame_id = self.state.wait_for_main_frame()
  let result = @client.cdp_response_result_json(
    self.client.send_schema_command("Page.createIsolatedWorld", params={
      "frameId": frame_id,
      "worldName": world_name,
      "grantUniveralAccess": grant_universal_access,
    }),
  )
  guard result is { "executionContextId": Number(context_id, ..), .. } else {
    raise @client.BrowserError::InvalidField("executionContextId")
  }
  { page: self, context_id: context_id.to_int() }
}

///|
/// Evaluates JavaScript once in this isolated world.
pub async fn IsolatedWorld::evaluate(
  self : IsolatedWorld,
  expression : String,
  await_promise? : Bool = false,
) -> Json {
  let response = self.page.client.send_schema_command("Runtime.evaluate", params={
    "expression": expression,
    "contextId": self.context_id,
    "returnByValue": true,
    "awaitPromise": await_promise,
  })
  self.page.evaluation_value(response, None)
}

///|
fn Page::evaluation_value(
  self : Page,
  response : @protocol.CdpResponseMessage,
  lease : ExecutionContextLease?,
) -> Json raise {
  if response.error is Some(error) {
    let lease_is_current = match lease {
      Some(value) => self.state.is_current(value)
      None => true
    }
    if is_execution_context_loss(error, lease_is_current) {
      if lease is Some(value) {
        self.state.invalidate(value)
      }
      raise PageLifecycleError::ContextLost
    }
    raise @client.BrowserError::CommandFailed(error.code, error.message)
  }
  let result = response.result.unwrap_or({})
  match result {
    { "exceptionDetails": exception, .. } =>
      raise JavaScriptError::Exception(exception)
    { "result": { "value": value, .. }, .. } => value
    { "result": { "type": "undefined", .. }, .. } => Json::null()
    _ => raise JavaScriptError::MissingValue(result)
  }
}

///|
fn is_execution_context_loss(
  error : @protocol.CdpError,
  lease_is_current : Bool,
) -> Bool {
  if !lease_is_current {
    return true
  }
  let message = error.message.to_lower()
  (error.code == -32000 && message.contains("context")) ||
  (
    error.code == -32602 &&
    message.contains("uniquecontextid") &&
    message.contains("not found")
  )
}

///|
fn PageState::handle_event(
  self : PageState,
  event : @protocol.CdpEventMessage,
) -> Unit {
  match event.method_name {
    "Runtime.executionContextCreated" => self.context_created(event.params)
    "Runtime.executionContextDestroyed" => self.context_destroyed(event.params)
    "Runtime.executionContextsCleared" => self.clear_context()
    "Page.frameNavigated" => self.frame_navigated(event.params)
    _ => ()
  }
}

///|
fn PageState::context_created(self : PageState, params : Json?) -> Unit {
  guard params is Some(params) else { return }
  let created = @typed.RuntimeExecutionContextCreatedEventParams::from_json(
    params,
  ) catch {
    _ => return
  }
  guard created.context.aux_data is Some(Object(aux_data)) else { return }
  guard aux_data is { "isDefault": True, "frameId": String(frame_id), .. } else {
    return
  }
  guard self.main_frame_id == Some(frame_id) else { return }
  self.generation = self.generation + 1UL
  self.context = Some({
    unique_id: created.context.unique_id,
    generation: self.generation,
  })
  self.changed.broadcast()
}

///|
fn PageState::context_destroyed(self : PageState, params : Json?) -> Unit {
  guard params is Some(params) else { return }
  let destroyed = @typed.RuntimeExecutionContextDestroyedEventParams::from_json(
    params,
  ) catch {
    _ => return
  }
  guard self.context is Some(context) &&
    context.unique_id == destroyed.execution_context_unique_id else {
    return
  }
  self.clear_context()
}

///|
fn PageState::frame_navigated(self : PageState, params : Json?) -> Unit {
  guard params is Some({ "frame": Object(frame), .. }) else { return }
  guard frame.get("parentId") is None else { return }
  guard frame.get("id") is Some(String(frame_id)) else { return }
  self.main_frame_id = Some(frame_id)
  self.clear_context()
}

///|
fn PageState::set_main_frame(self : PageState, frame_id : String) -> Unit {
  if self.main_frame_id != Some(frame_id) {
    self.main_frame_id = Some(frame_id)
    self.clear_context()
  }
}

///|
fn PageState::clear_context(self : PageState) -> Unit {
  self.generation = self.generation + 1UL
  self.context = None
  self.changed.broadcast()
}

///|
fn PageState::close(self : PageState) -> Unit {
  if !self.closed {
    self.closed = true
    self.context = None
    self.changed.broadcast()
  }
}

///|
async fn PageState::wait_for_context(self : PageState) -> ExecutionContextLease {
  while self.context is None && !self.closed {
    self.changed.wait()
  }
  match self.context {
    Some(context) => context
    None => raise PageLifecycleError::Closed
  }
}

///|
async fn PageState::wait_for_main_frame(self : PageState) -> String {
  while self.main_frame_id is None && !self.closed {
    self.changed.wait()
  }
  match self.main_frame_id {
    Some(frame_id) => frame_id
    None => raise PageLifecycleError::Closed
  }
}

///|
async fn PageState::wait_for_generation_after(
  self : PageState,
  generation : UInt64,
) -> Unit {
  while (self.context is None || self.generation <= generation) && !self.closed {
    self.changed.wait()
  }
  if self.closed {
    raise PageLifecycleError::Closed
  }
}

///|
fn PageState::is_current(
  self : PageState,
  lease : ExecutionContextLease,
) -> Bool {
  self.context is Some(current) &&
  current.generation == lease.generation &&
  current.unique_id == lease.unique_id
}

///|
fn PageState::invalidate(
  self : PageState,
  lease : ExecutionContextLease,
) -> Unit {
  if self.is_current(lease) {
    self.clear_context()
  }
}
