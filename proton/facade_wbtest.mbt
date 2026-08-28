///|
fn[T] unwrap_configuration(action : () -> T raise AppConfigurationError) -> T {
  action() catch {
    error => abort(error.message())
  }
}

///|
fn[T] unwrap_app_run(action : () -> T raise AppRunError) -> T {
  action() catch {
    error => abort(error.message())
  }
}

///|
fn[T] expect_configuration_error(
  action : () -> T raise AppConfigurationError,
) -> AppConfigurationError {
  try action() catch {
    error => error
  } noraise {
    _ => abort("expected application configuration error")
  }
}

///|
fn[T] expect_app_run_error(action : () -> T raise AppRunError) -> AppRunError {
  try action() catch {
    error => error
  } noraise {
    _ => abort("expected application run error")
  }
}

///|
priv suberror FacadeLifecycleTestError {
  DestroyFailed(String)
  StartFailed(String)
} derive(Debug)

///|
async fn test_open_window(id : String) -> WindowHandle raise WindowSessionError {
  @async.pause() catch {
    _ => raise UnknownWindow(id~)
  }
  raise UnknownWindow(id~)
}

///|
fn test_window_manager() -> WindowManager {
  WindowManager::{
    open_window: test_open_window,
    find_window: fn(_id) { None },
  }
}

///|
fn test_window_handle(
  id : String,
  native_id : Int64,
  position_calls? : Array[(Int, Int)],
  size_calls? : Array[(Int, Int)],
  popup_calls? : Array[String],
  progress_calls? : Array[Double],
  flash_calls? : Array[Bool],
  resizable_calls? : Array[Bool],
  movable_calls? : Array[Bool],
  opacity_calls? : Array[Double],
  skip_taskbar_calls? : Array[Bool],
  content_protection_calls? : Array[Bool],
  minimizable_calls? : Array[Bool],
  maximizable_calls? : Array[Bool],
  closable_calls? : Array[Bool],
  focusable_calls? : Array[Bool],
  fullscreenable_calls? : Array[Bool],
  has_shadow_calls? : Array[Bool],
  ignore_mouse_events_calls? : Array[(Bool, Bool)],
  background_color_calls? : Array[String],
  visible_on_all_workspaces_calls? : Array[Bool],
  enabled_calls? : Array[Bool],
  kiosk_calls? : Array[Bool],
  aspect_ratio_calls? : Array[Double],
  minimum_size_calls? : Array[(Int, Int)],
  maximum_size_calls? : Array[(Int, Int)],
  content_size_calls? : Array[(Int, Int)],
  content_size? : (Int, Int),
  window_state? : WindowState,
) -> WindowHandle {
  let browser = BrowserHandle::{
    id,
    native_id,
    load_browser_url: fn(_url) {  },
    load_browser_html: fn(_html, _base_url) {  },
    eval_browser_script: fn(_script) {  },
    send_browser_command: fn(_command, _download_id) {  },
  }
  WindowHandle::{
    id,
    native_id,
    show_window: fn() {  },
    hide_window: fn() {  },
    close_window: fn() {  },
    focus_window: fn() {  },
    set_window_title: fn(_title) {  },
    set_window_icon: fn(_path) {  },
    set_window_parent: fn(_parent, _modal) {  },
    set_window_size: (width, height) => {
      match size_calls {
        Some(calls) => calls.push((width, height))
        None => ()
      }
    },
    set_window_button_visibility: fn(_visible) {  },
    set_window_content_size: (width, height) => {
      match content_size_calls {
        Some(calls) => calls.push((width, height))
        None => ()
      }
    },
    read_window_content_size: fn() { content_size.unwrap_or((320, 240)) },
    set_window_menu: fn(_menu) {  },
    minimize_window: fn() {  },
    maximize_window: fn() {  },
    restore_window: fn() {  },
    set_window_fullscreen: fn(_fullscreen) {  },
    set_window_kiosk: kiosk => {
      match kiosk_calls {
        Some(calls) => calls.push(kiosk)
        None => ()
      }
    },
    set_window_position: (x, y) => {
      match position_calls {
        Some(calls) => calls.push((x, y))
        None => ()
      }
    },
    set_window_always_on_top: fn(_always_on_top) {  },
    set_window_resizable: resizable => {
      match resizable_calls {
        Some(calls) => calls.push(resizable)
        None => ()
      }
    },
    set_window_movable: movable => {
      match movable_calls {
        Some(calls) => calls.push(movable)
        None => ()
      }
    },
    set_window_opacity: opacity => {
      match opacity_calls {
        Some(calls) => calls.push(opacity)
        None => ()
      }
    },
    set_window_skip_taskbar: skip => {
      match skip_taskbar_calls {
        Some(calls) => calls.push(skip)
        None => ()
      }
    },
    set_window_content_protection: enabled => {
      match content_protection_calls {
        Some(calls) => calls.push(enabled)
        None => ()
      }
    },
    set_window_minimizable: minimizable => {
      match minimizable_calls {
        Some(calls) => calls.push(minimizable)
        None => ()
      }
    },
    set_window_maximizable: maximizable => {
      match maximizable_calls {
        Some(calls) => calls.push(maximizable)
        None => ()
      }
    },
    set_window_closable: closable => {
      match closable_calls {
        Some(calls) => calls.push(closable)
        None => ()
      }
    },
    set_window_focusable: focusable => {
      match focusable_calls {
        Some(calls) => calls.push(focusable)
        None => ()
      }
    },
    set_window_fullscreenable: fullscreenable => {
      match fullscreenable_calls {
        Some(calls) => calls.push(fullscreenable)
        None => ()
      }
    },
    set_window_has_shadow: has_shadow => {
      match has_shadow_calls {
        Some(calls) => calls.push(has_shadow)
        None => ()
      }
    },
    set_window_ignore_mouse_events: (ignore, forward) => {
      match ignore_mouse_events_calls {
        Some(calls) => calls.push((ignore, forward))
        None => ()
      }
    },
    set_window_background_color: color => {
      match background_color_calls {
        Some(calls) => calls.push(color)
        None => ()
      }
    },
    set_window_visible_on_all_workspaces: visible => {
      match visible_on_all_workspaces_calls {
        Some(calls) => calls.push(visible)
        None => ()
      }
    },
    set_window_enabled: enabled => {
      match enabled_calls {
        Some(calls) => calls.push(enabled)
        None => ()
      }
    },
    set_window_aspect_ratio: aspect_ratio => {
      match aspect_ratio_calls {
        Some(calls) => calls.push(aspect_ratio)
        None => ()
      }
    },
    set_window_minimum_size: (width, height) => {
      match minimum_size_calls {
        Some(calls) => calls.push((width, height))
        None => ()
      }
    },
    set_window_maximum_size: (width, height) => {
      match maximum_size_calls {
        Some(calls) => calls.push((width, height))
        None => ()
      }
    },
    set_window_zoom_percent: fn(_zoom_percent) {  },
    set_window_progress_bar: progress => {
      match progress_calls {
        Some(calls) => calls.push(progress)
        None => ()
      }
    },
    flash_window_frame: flash => {
      match flash_calls {
        Some(calls) => calls.push(flash)
        None => ()
      }
    },
    popup_window_menu: fn(menu, x, y) {
      match popup_calls {
        Some(calls) => {
          let (_, label, _) = menu.to_native().definition()
          let title = label.unwrap_or("")
          calls.push("popup:\{title}@\{x},\{y}")
        }
        None => ()
      }
    },
    read_window_state: match window_state {
      Some(state) => fn() { state }
      None => fn() { abort("test window state is not available") }
    },
    browser,
    add_view: fn(_id, _config) { abort("test views are not available") },
    remove_view: fn(_id) { abort("test views are not available") },
    list_views: fn() { [] },
    find_view: fn(_id) { None },
  }
}

///|
fn test_manifest() -> @manifest.AppManifest {
  @manifest.AppManifest(
    @manifest.WindowManifest("Test", 320, 240),
    @manifest.AppEntry::Html("<html></html>"),
  )
}

///|
test "last-window policy defaults to quit and can keep the app running" {
  let app = html("Lifecycle", "<html></html>")
  assert_eq(app.last_window_closed_policy_value, LastWindowClosedPolicy::Quit)
  let app = app.last_window_closed_policy(LastWindowClosedPolicy::KeepRunning)
  assert_eq(
    app.last_window_closed_policy_value,
    LastWindowClosedPolicy::KeepRunning,
  )
  assert_true(
    should_quit_after_last_window(LastWindowClosedPolicy::Quit, true, true),
  )
  assert_false(
    should_quit_after_last_window(
      LastWindowClosedPolicy::KeepRunning,
      true,
      true,
    ),
  )
  assert_false(
    should_quit_after_last_window(LastWindowClosedPolicy::Quit, false, true),
  )
}

///|
async test "application context forwards orderly quit requests" {
  let requested = Ref(false)
  @async.with_task_group(group => {
    let context = ApplicationContext(
      group,
      test_window_manager(),
      @locale.LocalePreferences::resolve(None, []),
      request_quit=fn() { requested.val = true },
    )
    context.quit()
    group.return_immediately(())
  })
  assert_true(requested.val)
}

///|
fn test_extension_capability(
  spec : @proton_command.AppCommandExtensionSpec,
  scope? : Json = Json::empty_object(),
  targets? : Array[RendererTarget] = [RendererTarget::entry()],
  definition_id? : UInt64 = 1UL,
  event_source? : @proton_extension.EventSource,
) -> ExtensionCapabilityBinding {
  ExtensionCapabilityBinding::{
    definition_id,
    spec,
    event_source,
    scope,
    targets,
  }
}

///|
fn test_build_command_host(
  command_capabilities : Array[AppCommandCapability],
  extension_capabilities : Array[ExtensionCapabilityBinding],
) -> CommandHostBuild raise AppRunError {
  let catalog = command_extension_catalog(extension_capabilities) catch {
    error => raise ConfigurationError(error)
  }
  build_command_host(command_capabilities, catalog)
}

///|
fn test_command_spec(
  extension_id : String,
  js_namespace : String,
  api_names : Array[String],
  dependencies? : Array[String] = [],
  scripts? : Array[String] = [],
  resolve_permission? : (Json, String) -> Json raise @proton_command.PermissionScopeValidationError,
  on_destroy? : () -> Unit raise = fn() {  },
) -> @proton_command.AppCommandExtensionSpec {
  let contract = @proton_contract.extension(id=extension_id, js_namespace~)
  let routes = api_names.map(fn(api_name) {
    let command : @proton_contract.Command[Json, Json] = contract.command(
      api_name,
    )
    command.contract_route()
  })
  @proton_command.AppCommandExtensionSpec::typed(
    contract,
    routes,
    fn(_registrar) {  },
    scripts~,
    dependencies~,
    resolve_permission?,
    on_destroy~,
  ) catch {
    error => abort(error.message())
  }
}

///|
fn test_tracking_command_spec(
  extension_id : String,
  js_namespace : String,
  registered : Array[String],
  dependencies? : Array[String] = [],
) -> @proton_command.AppCommandExtensionSpec {
  let contract = @proton_contract.extension(id=extension_id, js_namespace~)
  @proton_command.AppCommandExtensionSpec::typed(
    contract,
    [],
    fn(_registrar) { registered.push(extension_id) },
    dependencies~,
  ) catch {
    error => abort(error.message())
  }
}

///|
test "command proxy rejects unsafe JS property names" {
  assert_true(command_proxy_name_is_invalid(""))
  assert_true(command_proxy_name_is_invalid("   "))
  assert_true(command_proxy_name_is_invalid("core"))
  assert_true(command_proxy_name_is_invalid("events"))
  assert_true(command_proxy_name_is_invalid("__proto__"))
  assert_true(command_proxy_name_is_invalid("prototype"))
  assert_true(command_proxy_name_is_invalid("constructor"))
  assert_true(command_proxy_name_is_invalid("@@iterator"))
  assert_false(command_proxy_name_is_invalid("add"))
  assert_false(command_proxy_name_is_invalid("slowAdd"))
}

///|
test "bridge frontend config reflects enabled command extension metadata" {
  let extension_id = "examples/async-add"
  let spec = test_command_spec(extension_id, "add", ["slowAdd"])
  let config = unwrap_configuration(() => {
    bridge_frontend_config_for_extension(extension_id, spec)
  })
  inspect(config.extensions.length(), content="1")
  inspect(config.extensions[0].js_namespace, content="add")
  assert_eq(config.extensions[0].apis, ["slowAdd"])
  assert_eq(config.initialization_units, [])
}

///|
test "bridge frontend config preserves initialization unit ownership" {
  let extension_id = "examples/scripts"
  let spec = test_command_spec(extension_id, "scripts", [], scripts=[
    "globalThis.first = true;", "globalThis.second = true;",
  ])
  let config = unwrap_configuration(() => {
    bridge_frontend_config_for_extension(extension_id, spec)
  })
  inspect(config.initialization_units.length(), content="2")
  inspect(config.initialization_units[0].owner, content="examples/scripts")
  inspect(config.initialization_units[0].name, content="script-0")
  inspect(
    config.initialization_units[1].source,
    content="globalThis.second = true;",
  )
}

///|
test "app run errors retain typed bridge diagnostics" {
  let diagnostic = BridgeDiagnostic::{
    stage: "bootstrap",
    code: "bridge_bootstrap_failed",
    message: "bootstrap exploded",
    page_instance: "page-1",
    url: "proton://app/",
    owner: None,
    source_url: None,
    source_line: None,
    line: None,
    column: None,
    stack: None,
    additional_failure_count: None,
    details_truncated: false,
  }
  let error = BridgeStartupError(diagnostic)
  assert_true(error.message().contains("bridge_bootstrap_failed"))
}

///|
/// `fn init` installing the loop is what lets an application be a plain
/// `async fn main`. If it ever stops running, nothing else fails until
/// `App::run` refuses to start, so assert it directly.
test "the event loop is installed during process initialization" {
  require_event_loop()
}

///|
test "bridge startup timeout is finite and configurable" {
  let default_app = html("Test", "<html></html>").identifier("dev.proton.test")
  inspect(default_app.bridge_startup_timeout_value_ms, content="30000")
  let configured = default_app.bridge_startup_timeout_ms(2500)
  inspect(configured.bridge_startup_timeout_value_ms, content="2500")
  assert_true(configured.validation_error() is None)
  match configured.bridge_startup_timeout_ms(0).validation_error() {
    Some(InvalidSetting(name~, message~)) => {
      assert_eq(name, "bridge_startup_timeout_ms")
      assert_eq(message, "must be positive")
    }
    _ => fail("expected invalid timeout setting")
  }
}

///|
test "debug mode uses an ephemeral endpoint unless a fixed port is explicit" {
  assert_eq(
    resolve_remote_debugging(0, None),
    @native.RemoteDebugging::Disabled,
  )
  assert_eq(
    resolve_remote_debugging(1, None),
    @native.RemoteDebugging::Ephemeral,
  )
  assert_eq(
    resolve_remote_debugging(1, Some("0")),
    @native.RemoteDebugging::Ephemeral,
  )
  assert_eq(
    resolve_remote_debugging(1, Some(" 9333 ")),
    @native.RemoteDebugging::Fixed(9333),
  )
}

///|
test "debug mode rejects invalid fixed ports instead of falling back" {
  for value in ["invalid", "-1", "1023", "65536"] {
    try ignore(resolve_remote_debugging(1, Some(value))) catch {
      InvalidSetting(name="PROTON_REMOTE_DEBUGGING_PORT", ..) => ()
      _ => fail("expected an invalid remote debugging port")
    } noraise {
      _ => fail("expected an invalid remote debugging port")
    }
  }
}

///|
test "headless mode defaults off and is configurable" {
  let default_app = html("Test", "<html></html>")
  assert_false(default_app.headless_value)
  assert_true(default_app.headless().headless_value)
  assert_false(default_app.headless(enabled=false).headless_value)
}

///|
async test "headless mode rejects titlebar overlay before runtime startup" {
  let manifest = @manifest.AppManifest(
    @manifest.WindowManifest(
      "Test",
      320,
      240,
      titlebar_style=@manifest.TitlebarStyle::Overlay,
    ),
    @manifest.AppEntry::Html("<html></html>"),
  )
  let mut rejected = false
  run_manifest(
    manifest,
    ".",
    [],
    [],
    [],
    [],
    None,
    30000,
    true,
    @locale.LocalePreferences::resolve(None, []),
  ) catch {
    ConfigurationError(InvalidSetting(name="headless", message~)) => {
      rejected = true
      assert_eq(message, "titlebar overlay is not supported in headless mode")
    }
    error =>
      fail("expected configuration error, got " + @debug.render(Repr(error)))
  }
  assert_true(rejected)
}

///|
async test "headless mode rejects native menus before runtime startup" {
  let manifest = test_manifest()
  let menu = MenuBar(menus=[
    Menu("App", items=[MenuItem::role(MenuItemRole::Close, label="Close")]),
  ])
  let mut rejected = false
  run_manifest(
    manifest,
    ".",
    [],
    [],
    [],
    [],
    Some(menu.to_native()),
    30000,
    true,
    @locale.LocalePreferences::resolve(None, []),
  ) catch {
    ConfigurationError(InvalidSetting(name="headless", message~)) => {
      rejected = true
      assert_eq(message, "native menus are not supported in headless mode")
    }
    error =>
      fail("expected configuration error, got " + @debug.render(Repr(error)))
  }
  assert_true(rejected)
}

///|
test "bridge startup timeout retains the last lifecycle state" {
  let state = @native.BridgeLifecycleState::{
    abi_version: 1,
    revision: "7",
    outcome: "pending",
    page_instance: "page-1",
    url: "proton://app/",
    failure_pending: false,
  }
  let diagnostic = bridge_startup_timeout_diagnostic(state, 2500)
  assert_eq(diagnostic.stage, "prepare")
  assert_eq(diagnostic.code, "bridge_startup_timeout")
  assert_eq(diagnostic.page_instance, "page-1")
  assert_eq(diagnostic.url, "proton://app/")
  assert_true(diagnostic.message.contains("2500 ms"))
}

///|
async test "bridge cancellation targets only the matching handler task" {
  @async.with_task_group(group => {
    let first_task = group.spawn(
      () => {
        @async.sleep(10000)
        @native.BridgeResponse::Ok(request_id=41L, payload=null)
      },
      no_wait=true,
      allow_failure=true,
    )
    let second_task = group.spawn(
      () => {
        @async.sleep(10000)
        @native.BridgeResponse::Ok(request_id=42L, payload=null)
      },
      no_wait=true,
      allow_failure=true,
    )
    let pending = [
      BridgeDispatchTask::{
        request_id: 41L,
        window: 1L,
        task: first_task,
        state: Running,
      },
      BridgeDispatchTask::{
        request_id: 42L,
        window: 1L,
        task: second_task,
        state: Running,
      },
    ]
    runtime_session_cancel_bridge_request(pending, Some(42L))
    assert_true(pending[0].state is Running)
    assert_true(pending[1].state is Cancelled)
    first_task.cancel()
    group.return_immediately(())
  })
}

///|
test "extension events use structured bridge transport JSON" {
  let event = @ipc.IpcExtensionEvent("ticker", "tick", {
    "text": "</script><p>escaped</p>",
    "index": 1,
  })
  let event_json = bridge_event_json(
    "extension",
    event.event_name,
    event.payload,
    Some(event.extension_namespace),
    None,
  )
  assert_true(event_json.contains("\"kind\":\"extension\""))
  assert_true(event_json.contains("\"extension\":\"ticker\""))
  assert_true(event_json.contains("\"name\":\"tick\""))
  assert_true(event_json.contains("\"text\":\"</script><p>escaped</p>\""))
}

///|
test "file entry only injects a base URL for relative assets" {
  let html =
    #|<html><head><link rel="stylesheet" href="app.css"></head><body><script src="app.js"></script></body></html>
  let injected = inject_html_bootstrap(
    html,
    base_tag("proton://app/D:/Code/proton-demo/app/"),
  )
  assert_true(
    injected.contains(
      "<head>\n<base href=\"proton://app/D:/Code/proton-demo/app/\">",
    ),
  )
  assert_true(injected.contains("href=\"app.css\""))
  assert_true(injected.contains("src=\"app.js\""))
  assert_false(injected.contains("__MoonBit__"))
}

///|
test "base tags escape HTML attributes" {
  inspect(
    base_tag("file:///tmp/a&b\"c/"),
    content="<base href=\"file:///tmp/a&amp;b&quot;c/\">\n",
  )
}

///|
test "asset urls expose a document root instead of the local file path" {
  let path = "46_asset_sidecar_resources/app/app.html"
  let file_path = resolve_asset_path(path)
  let base = asset_base_url().replace_all(old="\\", new="/")
  let document = asset_document_url(file_path).replace_all(old="\\", new="/")
  inspect(base, content="https://proton.localhost/")
  inspect(document, content="https://proton.localhost/app.html")
  assert_eq(file_path.dirname().basename().to_owned(), "app")
}

///|
test "asset url path encoding escapes browser url delimiters" {
  inspect(
    asset_url_path_encode("C:/tmp/a b/#?%/中.html"),
    content="C:/tmp/a%20b/%23%3f%25/%e4%b8%ad.html",
  )
}

///|
test "resource urls decode paths without query or fragment data" {
  assert_eq(
    resource_url_path(
      "https://proton.localhost/assets/a%20b/%e4%b8%ad.js?version=1#entry",
    ),
    Some("assets/a b/中.js"),
  )
}

///|
test "resource urls reject traversal and malformed encodings" {
  assert_eq(resource_url_path("https://proton.localhost/../secret"), None)
  assert_eq(
    resource_url_path("https://proton.localhost/assets/%2e%2e/secret"),
    None,
  )
  assert_eq(resource_url_path("https://proton.localhost/%2fetc/passwd"), None)
  assert_eq(resource_url_path("https://proton.localhost/%00.txt"), None)
  assert_eq(resource_url_path("https://proton.localhost/%zz.txt"), None)
}

///|
test "resource root containment requires a path boundary" {
  let separator = @mbpath.sep.to_string()
  let root = separator + "tmp" + separator + "app"
  assert_true(
    resource_path_is_under_root(root + separator + "index.html", root),
  )
  assert_true(resource_path_is_under_root(root, root))
  assert_true(
    resource_path_is_under_root(
      separator + "tmp" + separator + "file",
      separator,
    ),
  )
  assert_false(
    resource_path_is_under_root(
      root + "-other" + separator + "index.html",
      root,
    ),
  )
}

///|
test "resource mime types cover browser assets" {
  assert_eq(resource_mime_type("main.CSS"), "text/css")
  assert_eq(resource_mime_type("main.mjs"), "text/javascript")
  assert_eq(resource_mime_type("font.woff2"), "font/woff2")
  assert_eq(resource_mime_type("data.bin"), "application/octet-stream")
}

///|
async test "inline documents resolve without filesystem access" {
  let document = ResourceDocument::{
    url: "proton://view/",
    content: b"<h1>view</h1>",
  }
  let response = resolve_resource_request(
    Some(document),
    None,
    "proton://view/",
  )
  assert_eq(response.status, 200)
  assert_eq(response.mime_type, "text/html")
  assert_eq(response.body, b"<h1>view</h1>")
}

///|
test "extension event transport can target a page instance" {
  let event = @ipc.IpcExtensionEvent("ticker", "done", null)
  let event_json = bridge_event_json(
    "extension",
    event.event_name,
    event.payload,
    Some(event.extension_namespace),
    Some("page-1"),
  )
  assert_true(event_json.contains("\"page_instance\":\"page-1\""))
}

///|
test "frontend menu event transport preserves focused window" {
  let event_json = bridge_event_json(
    "frontend",
    "menu.command",
    { "command_id": "demo.refresh", "window": "17" },
    None,
    None,
  )
  assert_true(event_json.contains("\"kind\":\"frontend\""))
  assert_true(event_json.contains("\"name\":\"menu.command\""))
  assert_true(event_json.contains("\"command_id\":\"demo.refresh\""))
  assert_true(event_json.contains("\"window\":\"17\""))
}

///|
test "frontend event forwarding ignores only closing window errors" {
  assert_true(
    is_ignorable_frontend_event_forward_error(
      @native.NativeError::Status(
        status=-3,
        message="window is closing or destroyed",
      ),
    ),
  )
  assert_true(
    is_ignorable_frontend_event_forward_error(
      @native.NativeError::Status(
        status=-13,
        message="window close request is no longer pending",
      ),
    ),
  )
  assert_false(
    is_ignorable_frontend_event_forward_error(
      @native.NativeError::Status(
        status=-7,
        message="failed to send bridge event to renderer",
      ),
    ),
  )
  assert_false(
    is_ignorable_frontend_event_forward_error(
      @native.NativeError::InvalidArgument(message="invalid event"),
    ),
  )
}

///|
fn test_activation_window_state(
  visible? : Bool = true,
  minimized? : Bool = false,
) -> @native.WindowState {
  @native.WindowState::{
    x: 0,
    y: 0,
    width: 800,
    height: 600,
    monitor: @native.WindowMonitor::{
      x: 0,
      y: 0,
      width: 1920,
      height: 1080,
      work_x: 0,
      work_y: 0,
      work_width: 1920,
      work_height: 1040,
      scale_factor_percent: 100,
    },
    zoom_percent: 100,
    visible,
    focused: false,
    minimized,
    maximized: false,
    fullscreen: false,
    always_on_top: false,
    theme: "system",
  }
}

///|
fn test_launch_activation_ignores_status(
  status : Int,
) -> Array[(Bool, Array[String])] {
  let results : Array[(Bool, Array[String])] = []
  for stage in ["state", "restore", "show", "focus"] {
    let calls : Array[String] = []
    let activated = unwrap_app_run(() => {
      try_activate_for_launch_input(
        () => {
          if stage == "state" {
            raise @native.NativeError::Status(
              status~,
              message="window is no longer usable",
            )
          }
          test_activation_window_state(
            visible=stage != "show",
            minimized=stage == "restore",
          )
        },
        () => {
          calls.push("restore")
          if stage == "restore" {
            raise @native.NativeError::Status(
              status~,
              message="window is no longer usable",
            )
          }
        },
        () => {
          calls.push("show")
          if stage == "show" {
            raise @native.NativeError::Status(
              status~,
              message="window is no longer usable",
            )
          }
        },
        () => {
          calls.push("focus")
          if stage == "focus" {
            raise @native.NativeError::Status(
              status~,
              message="window is no longer usable",
            )
          }
        },
      )
    })
    results.push((activated, calls))
  }
  results
}

///|
test "launch activation skips invalid native windows at every stage" {
  for status in [-3, -13] {
    let results = test_launch_activation_ignores_status(status)
    assert_eq(results.length(), 4)
    for index = 0; index < results.length(); index = index + 1 {
      let (activated, calls) = results[index]
      assert_false(activated)
      let expected_calls = match index {
        0 => []
        1 => ["restore"]
        2 => ["show"]
        _ => ["focus"]
      }
      assert_eq(calls, expected_calls)
    }
  }
}

///|
test "launch activation preserves unexpected native errors" {
  let calls : Array[String] = []
  let error = expect_app_run_error(() => {
    ignore(
      try_activate_for_launch_input(
        () => test_activation_window_state(),
        () => (),
        () => (),
        () => {
          calls.push("focus")
          raise @native.NativeError::Status(
            status=-7,
            message="failed to focus window",
          )
        },
      ),
    )
  })
  match error {
    RuntimeOperationFailed(action~, status~, detail~) => {
      assert_eq(action, "focus activation window")
      assert_eq(status, -7)
      assert_eq(detail, "failed to focus window")
      assert_eq(calls, ["focus"])
    }
    _ => fail("expected unexpected native error")
  }
}

///|
test "launch activation restores shows and focuses in order" {
  let calls : Array[String] = []
  let activated = unwrap_app_run(() => {
    try_activate_for_launch_input(
      () => test_activation_window_state(visible=false, minimized=true),
      () => calls.push("restore"),
      () => calls.push("show"),
      () => calls.push("focus"),
    )
  })
  assert_true(activated)
  assert_eq(calls, ["restore", "show", "focus"])
}

///|
test "dev bridge page policy parses exact http origins" {
  assert_eq(
    unwrap_configuration(() => url_origin("http://localhost:5173/app")),
    "http://localhost:5173",
  )
  assert_eq(
    unwrap_configuration(() => url_origin("https://localhost/app")),
    "https://localhost",
  )
  assert_eq(
    unwrap_configuration(() => url_origin("http://127.0.0.1:3000")),
    "http://127.0.0.1:3000",
  )
  assert_eq(
    unwrap_configuration(() => url_origin("http://[::1]:5173/app")),
    "http://[::1]:5173",
  )
  assert_eq(
    unwrap_configuration(() => url_origin("HTTP://LOCALHOST:80/app")),
    "http://localhost",
  )
  assert_eq(
    unwrap_configuration(() => url_origin("https://Example.COM:443/app")),
    "https://example.com",
  )
  assert_eq(
    unwrap_configuration(() => url_origin("http://LOCALHOST:05173/app")),
    "http://localhost:5173",
  )
  for
    item in [
      ("ftp://localhost:5173/app", "http or https"),
      ("http://local\"host:5173/app", "invalid origin"),
      ("http://local\\host:5173/app", "invalid origin"),
      ("http://localhost:/app", "port must not be empty"),
      ("http://[::1]5173/app", "invalid IPv6 origin"),
    ] {
    let (url, expected_reason) = item
    match expect_configuration_error(() => url_origin(url)) {
      InvalidEntryUrl(reason~, ..) =>
        assert_true(reason.contains(expected_reason))
      error => fail(error.message())
    }
  }
}

///|
test "native bridge config isolates each window entry origin" {
  let first = native_bridge_config([
    @native.BridgeGrantConfig("http://localhost:3000", ops=["app:ping"]),
  ])
  let second = native_bridge_config([
    @native.BridgeGrantConfig("http://localhost:4000", ops=["app:ping"]),
  ])
  inspect(first.grants[0].source_origin, content="http://localhost:3000")
  inspect(second.grants[0].source_origin, content="http://localhost:4000")
}

///|
test "HTTP entry capabilities use the exact canonical origin" {
  let policy = unwrap_configuration(() => {
    bridge_page_policy_for_entry(
      @manifest.AppEntry::Url("HTTPS://Example.COM:443/app"),
    )
  })
  assert_eq(policy.entry_origin, Some("https://example.com"))
}

///|
test "replacing an entry preserves renderer capabilities" {
  let replaced = asset("Development", "app.html")
    .commands(fn(_registrar) {  })
    .entry_url("http://localhost:5173")
  assert_eq(replaced.command_capabilities.length(), 1)
  assert_eq(replaced.command_capabilities[0].targets.length(), 1)
  assert_eq(replaced.command_capabilities[0].targets[0].window, "main")
  assert_false(replaced.command_capabilities[0].targets[0].bundled)
}

///|
test "renderer policy binds extension ops and scope to one trusted source" {
  let extension_id = "examples/scoped"
  let capability = test_extension_capability(
    test_command_spec(extension_id, "scoped", ["read"], resolve_permission=fn(
      scope,
      base_path,
    ) {
      { "base_path": base_path, "scope": scope }
    }),
    scope={ "root": "./data" },
  )
  let resolved = unwrap_configuration(() => {
    resolve_extension_capabilities([capability], "/trusted/project")
  })
  let policy = unwrap_configuration(() => {
    resolve_window_permission_policy(
      "main",
      BridgePagePolicy::{ entry_origin: None, },
      [],
      resolved,
    )
  })
  assert_eq(policy.grants.length(), 1)
  assert_eq(policy.grants[0].source_origin, "app")
  assert_eq(policy.grants[0].ops, ["ext:scoped/read"])
  inspect(
    policy.grants[0].scope.stringify(),
    content="{\"base_path\":\"/trusted/project\",\"scope\":{\"root\":\"./data\"}}",
  )
  assert_true(policy.grant_for_request("app", "ext:scoped/read") is Some(_))
  assert_true(
    policy.grant_for_request("https://example.com", "ext:scoped/read") is None,
  )
  assert_true(policy.grant_for_request("app", "app:read") is None)
}

///|
test "one extension supports distinct scopes in different windows" {
  let extension_id = "examples/window-scopes"
  let registered = Ref(0)
  let contract = @proton_contract.extension(
    id=extension_id,
    js_namespace="windowScopes",
  )
  let read : @proton_contract.Command[Unit, Unit] = contract.command("read")
  let spec = @proton_command.AppCommandExtensionSpec::typed(
    contract,
    [read.contract_route()],
    fn(registrar) raise {
      registered.val = registered.val + 1
      registrar.bind(read, (_context, _request) => ())
    },
    resolve_permission=fn(scope, _base_path) { scope },
  ) catch {
    error => abort(error.message())
  }
  let capabilities = [
    test_extension_capability(spec, scope={ "root": "./main" }),
    test_extension_capability(spec, scope={ "root": "./secondary" }, targets=[
      RendererTarget::entry(window="secondary"),
    ]),
  ]
  let resolved = unwrap_configuration(() => {
    resolve_extension_capabilities(capabilities, "/trusted/project")
  })
  let build = unwrap_app_run(() => test_build_command_host([], capabilities))
  assert_eq(registered.val, 1)
  let main_policy = unwrap_configuration(() => {
    resolve_window_permission_policy(
      "main",
      BridgePagePolicy::{ entry_origin: None, },
      [],
      resolved,
    )
  })
  let secondary_policy = unwrap_configuration(() => {
    resolve_window_permission_policy(
      "secondary",
      BridgePagePolicy::{ entry_origin: None, },
      [],
      resolved,
    )
  })
  assert_true(main_policy.grants_extension(extension_id))
  assert_true(secondary_policy.grants_extension(extension_id))
  assert_false(main_policy.grants_extension("examples/other-extension"))
  inspect(
    main_policy.grants[0].scope.stringify(),
    content="{\"root\":\"./main\"}",
  )
  inspect(
    secondary_policy.grants[0].scope.stringify(),
    content="{\"root\":\"./secondary\"}",
  )
  ignore(close_command_host(build.runtime))
}

///|
test "application commands grant the primary entry by default" {
  let ping : @proton_contract.Command[Unit, String] = @proton_contract.command(
    "ping",
  )
  let configured = html("Commands", "<html></html>").commands(registrar => {
    registrar.bind(ping, (_context, _request) => "pong")
  })
  let build = unwrap_app_run(() => {
    test_build_command_host(configured.command_capabilities, [])
  })
  let policy = resolve_window_permission_policy(
    "main",
    BridgePagePolicy::{ entry_origin: None, },
    build.app_capabilities,
    [],
  )
  assert_true(policy.grant_for_request("app", "app:ping") is Some(_))
  ignore(close_command_host(build.runtime))
}

///|
test "omitted renderer capabilities are a valid empty policy" {
  let manifest = test_manifest()
  unwrap_configuration(() => {
    validate_renderer_capability_targets(manifest, [], [])
  })
  let build = unwrap_app_run(() => test_build_command_host([], []))
  assert_true(build.runtime is None)
  let policy = resolve_window_permission_policy(
    "main",
    BridgePagePolicy::{ entry_origin: None, },
    build.app_capabilities,
    [],
  )
  assert_eq(policy.grants.length(), 0)
}

///|
test "application command registrars retain separate renderer targets" {
  let primary : @proton_contract.Command[Unit, String] = @proton_contract.command(
    "primary",
  )
  let secondary : @proton_contract.Command[Unit, String] = @proton_contract.command(
    "secondary",
  )
  let configured = html("Commands", "<html></html>")
    .add_window("secondary", "Secondary", AppEntry::Html("<html></html>"))
    .commands(registrar => {
      registrar.bind(primary, (_context, _request) => "primary")
    })
    .commands(
      registrar => {
        registrar.bind(secondary, (_context, _request) => "secondary")
      },
      targets=[RendererTarget::entry(window="secondary")],
    )
  let build = unwrap_app_run(() => {
    test_build_command_host(configured.command_capabilities, [])
  })
  let primary_policy = resolve_window_permission_policy(
    "main",
    BridgePagePolicy::{ entry_origin: None, },
    build.app_capabilities,
    [],
  )
  let secondary_policy = resolve_window_permission_policy(
    "secondary",
    BridgePagePolicy::{ entry_origin: None, },
    build.app_capabilities,
    [],
  )
  assert_true(primary_policy.grant_for_request("app", "app:primary") is Some(_))
  assert_true(primary_policy.grant_for_request("app", "app:secondary") is None)
  assert_true(
    secondary_policy.grant_for_request("app", "app:secondary") is Some(_),
  )
  assert_true(secondary_policy.grant_for_request("app", "app:primary") is None)
  ignore(close_command_host(build.runtime))
}

///|
test "renderer capabilities reject unknown windows" {
  let configured = html("Unknown window", "<html></html>").commands(
    fn(_registrar) {  },
    targets=[RendererTarget::entry(window="missing")],
  )
  match
    expect_configuration_error(() => {
      validate_renderer_capability_targets(
        configured.inline_manifest(),
        configured.command_capabilities,
        [],
      )
    }) {
    InvalidRendererCapability(detail~) =>
      assert_true(detail.contains("unknown window missing"))
    error => fail(error.message())
  }
}

///|
test "renderer capabilities reject targets that resolve to the same origin" {
  let capability = test_extension_capability(
    test_command_spec("examples/duplicate-origin", "duplicateOrigin", ["read"]),
    targets=[RendererTarget::entry(), RendererTarget::bundled()],
  )
  let resolved = unwrap_configuration(() => {
    resolve_extension_capabilities([capability], "/trusted/project")
  })
  match
    expect_configuration_error(() => {
      resolve_window_permission_policy(
        "main",
        BridgePagePolicy::{ entry_origin: None, },
        [],
        resolved,
      )
    }) {
    InvalidRendererCapability(detail~) =>
      assert_true(detail.contains("repeats source app"))
    error => fail(error.message())
  }
}

///|
test "extension capability scopes are validated before startup" {
  let extension_id = "examples/unscoped"
  let capability = test_extension_capability(
    test_command_spec(extension_id, "unscoped", ["read"]),
    scope={ "unexpected": true },
  )
  match
    expect_configuration_error(() => {
      ignore(resolve_extension_capabilities([capability], "/trusted/project"))
    }) {
    InvalidRendererCapability(detail~) =>
      assert_true(
        detail.contains("does not accept a non-empty permission scope"),
      )
    error => fail(error.message())
  }
}

///|
test "command host close runs extension destroy hooks once" {
  let extension_id = "examples/destroy"
  let destroyed = Ref(0)
  let contract = @proton_contract.extension(
    id=extension_id,
    js_namespace="destroyTest",
  )
  let ping : @proton_contract.Command[Unit, String] = contract.command("ping")
  let spec = @proton_command.AppCommandExtensionSpec::typed(
    contract,
    [ping.contract_route()],
    fn(registrar) raise { registrar.bind(ping, (_context, _request) => "pong") },
    on_destroy=fn() { destroyed.val = destroyed.val + 1 },
  ) catch {
    error => abort(error.message())
  }
  let build = unwrap_app_run(() => {
    test_build_command_host([], [test_extension_capability(spec)])
  })
  match build.runtime {
    Some(host) => {
      ignore(close_command_host(Some(host)))
      assert_eq(destroyed.val, 1)
      ignore(close_command_host(Some(host)))
      assert_eq(destroyed.val, 1)
    }
    None => fail("expected command host")
  }
}

///|
test "command host stops event sources before extension destroy hooks" {
  let lifecycle : Array[String] = []
  let spec = test_command_spec(
    "examples/event-source-lifecycle",
    "eventSourceLifecycle",
    ["ping"],
    on_destroy=fn() { lifecycle.push("destroy") },
  )
  let source = @proton_extension.event_source(
    _wakeup => lifecycle.push("start"),
    () => lifecycle.push("stop"),
    () => [],
  )
  let build = unwrap_app_run(() => {
    test_build_command_host([], [
      test_extension_capability(spec, event_source=source),
    ])
  })
  match build.runtime {
    Some(host) => {
      unwrap_app_run(() => {
        start_command_extension_event_sources(
          host.event_sources,
          @native.event_wakeup_callback(),
        )
      })
      assert_eq(lifecycle, ["start"])
      assert_eq(close_command_host(Some(host)).length(), 0)
      assert_eq(lifecycle, ["start", "stop", "destroy"])
      assert_eq(close_command_host(Some(host)).length(), 0)
      assert_eq(lifecycle, ["start", "stop", "destroy"])
    }
    None => fail("expected command host")
  }
}

///|
test "event source startup failure runs its teardown" {
  let lifecycle : Array[String] = []
  let source = @proton_extension.event_source(
    _wakeup => {
      lifecycle.push("start")
      raise FacadeLifecycleTestError::StartFailed("event source")
    },
    () => lifecycle.push("stop"),
    () => [],
  )
  let event_sources = [
    CommandExtensionEventSource::{
      extension_id: "examples/start-failure",
      extension_namespace: "startFailure",
      source,
      started: false,
    },
  ]
  match
    expect_app_run_error(() => {
      start_command_extension_event_sources(
        event_sources,
        @native.event_wakeup_callback(),
      )
    }) {
    CommandExtensionLifecycleError(EventSourceStartFailed(..)) => ()
    error => fail(error.message())
  }
  assert_eq(lifecycle, ["start", "stop"])
  assert_false(event_sources[0].started)
}

///|
test "duplicate extension event sources require the same definition" {
  let spec = test_command_spec(
    "examples/definition-identity",
    "definitionIdentity",
    ["ping"],
  )
  let source = @proton_extension.event_source(_wakeup => (), () => (), () => [])
  match
    expect_configuration_error(() => {
      ignore(
        command_extension_catalog([
          test_extension_capability(
            spec,
            definition_id=1UL,
            event_source=source,
          ),
          test_extension_capability(
            spec,
            definition_id=2UL,
            event_source=source,
          ),
        ]),
      )
    }) {
    InvalidRendererCapability(detail~) =>
      assert_true(detail.contains("conflicting event sources"))
    error => fail(error.message())
  }
}

///|
test "duplicate renderer capabilities may share one extension event source" {
  let spec = test_command_spec(
    "examples/shared-event-source",
    "sharedEventSource",
    ["ping"],
  )
  let source = @proton_extension.event_source(_wakeup => (), () => (), () => [])
  let capabilities = [
    test_extension_capability(spec, definition_id=7UL, event_source=source),
    test_extension_capability(spec, definition_id=7UL, event_source=source),
  ]
  let catalog = unwrap_configuration(() => {
    command_extension_catalog(capabilities)
  })
  assert_eq(catalog.specs.length(), 1)
  match catalog.event_sources.get(spec.id()) {
    Some(_) => ()
    None => fail("expected shared event source")
  }
}

///|
test "event-only extensions still create a renderer bridge host" {
  let spec = test_command_spec("examples/event-only", "eventOnly", [])
  let source = @proton_extension.event_source(_wakeup => (), () => (), () => [])
  let build = unwrap_app_run(() => {
    test_build_command_host([], [
      test_extension_capability(spec, event_source=source),
    ])
  })
  match build.runtime {
    Some(host) => {
      assert_eq(host.host.registered_ops(), [])
      assert_eq(host.event_sources.length(), 1)
      assert_true(requires_renderer_bridge(Some(host), false, false))
      assert_eq(close_command_host(Some(host)).length(), 0)
    }
    None => fail("expected event-only extension to require a bridge host")
  }
}

///|
test "renderer bridge requirement includes every bridge-owned feature" {
  assert_false(requires_renderer_bridge(None, false, false))
  assert_true(requires_renderer_bridge(None, true, false))
  assert_true(requires_renderer_bridge(None, false, true))
}

///|
test "command host installs typed application registrars before sealing" {
  let ping : @proton_contract.Command[Unit, String] = @proton_contract.command(
    "ping",
  )
  let capabilities = [
    AppCommandCapability::{
      register: registrar => {
        registrar.bind(ping, (_context, _request) => "pong")
      },
      targets: [RendererTarget::entry()],
    },
  ]
  let build = unwrap_app_run(() => test_build_command_host(capabilities, []))
  assert_eq(build.app_capabilities.length(), 1)
  assert_eq(build.app_capabilities[0].ops, ["app:ping"])
  match build.runtime {
    Some(host) => {
      assert_eq(host.host.registered_ops(), ["app:ping"])
      ignore(close_command_host(Some(host)))
    }
    None => fail("expected application command host")
  }
}

///|
test "command host close drains every destroy hook after a failure" {
  let base_id = "examples/base-destroy"
  let feature_id = "examples/feature-destroy"
  let destroyed : Array[String] = []
  let base_spec = @proton_command.AppCommandExtensionSpec::typed(
    @proton_contract.extension(id=base_id, js_namespace="baseDestroy"),
    [],
    fn(_registrar) {  },
    on_destroy=fn() { destroyed.push(base_id) },
  ) catch {
    error => abort(error.message())
  }
  let feature_spec = @proton_command.AppCommandExtensionSpec::typed(
    @proton_contract.extension(id=feature_id, js_namespace="featureDestroy"),
    [],
    fn(_registrar) {  },
    dependencies=[base_id],
    on_destroy=fn() raise {
      destroyed.push(feature_id)
      raise FacadeLifecycleTestError::DestroyFailed(feature_id)
    },
  ) catch {
    error => abort(error.message())
  }
  let build = unwrap_app_run(() => {
    test_build_command_host([], [
      test_extension_capability(base_spec),
      test_extension_capability(feature_spec),
    ])
  })
  match build.runtime {
    Some(host) => {
      let failures = close_command_host(Some(host))
      assert_eq(destroyed, [feature_id, base_id])
      assert_eq(failures.length(), 1)
      match failures[0] {
        DestroyFailed(extension_id~, ..) => assert_eq(extension_id, feature_id)
        _ => fail("expected extension destroy failure")
      }
      assert_eq(close_command_host(Some(host)).length(), 0)
      assert_eq(destroyed, [feature_id, base_id])
    }
    None => fail("expected command host")
  }
}

///|
test "command host registration preserves cleanup failures" {
  let extension_id = "examples/registration-cleanup"
  let spec = @proton_command.AppCommandExtensionSpec::typed(
    @proton_contract.extension(
      id=extension_id,
      js_namespace="registrationCleanup",
    ),
    [],
    fn(_registrar) raise {
      raise FacadeLifecycleTestError::DestroyFailed("registration")
    },
    on_destroy=fn() raise {
      raise FacadeLifecycleTestError::DestroyFailed("cleanup")
    },
  ) catch {
    error => abort(error.message())
  }
  let error = expect_app_run_error(() => {
    ignore(test_build_command_host([], [test_extension_capability(spec)]))
  })
  match error {
    CleanupFailed(primary~, failures~) => {
      assert_true(primary.unwrap_or("").contains("registration"))
      assert_eq(failures.length(), 1)
      match failures[0] {
        CommandExtension(DestroyFailed(extension_id=failed_id, ..)) =>
          assert_eq(failed_id, extension_id)
        _ => fail("expected extension cleanup failure")
      }
    }
    _ => fail("expected combined registration and cleanup failure")
  }
}

///|
test "application lifecycle advances through close and destroy" {
  let lifecycle = AppLifecycle()
  assert_true(lifecycle.state is Constructing)
  assert_false(lifecycle.has_reached_running())
  lifecycle.begin_starting()
  assert_false(lifecycle.has_reached_running())
  lifecycle.begin_running()
  assert_true(lifecycle.state is Running)
  assert_true(lifecycle.has_reached_running())
  lifecycle.observe_window_closed()
  assert_true(lifecycle.state is Closing)
  lifecycle.begin_draining()
  lifecycle.begin_destroying()
  lifecycle.finish()
  assert_true(lifecycle.state is Closed)
}

///|
async test "application lifecycle hooks shut down in reverse order" {
  let calls : Array[String] = []
  let configured = html("Lifecycle", "<html></html>")
    .app_lifecycle(
      on_start=fn(_context) {
        calls.push("start:first")
        "first"
      },
      on_shutdown=fn(state) { calls.push("stop:" + state) },
    )
    .app_lifecycle(
      on_start=fn(_context) {
        calls.push("start:second")
        "second"
      },
      on_shutdown=fn(state) { calls.push("stop:" + state) },
    )
  @async.with_task_group(group => {
    start_application_lifecycle_hooks(
      configured.application_lifecycle_hooks,
      ApplicationContext(
        group,
        test_window_manager(),
        @locale.LocalePreferences::resolve(None, []),
      ),
      group,
      [],
    )
    group.return_immediately(())
  })
  assert_eq(calls, ["start:first", "start:second", "stop:second", "stop:first"])
}

///|
async test "runtime wakeup preserves notification before suspension" {
  let wakeup = RuntimeWakeup::{ signal: @core.RuntimeWakeSignal(), }
  let revision = wakeup.revision()
  wakeup.signal.notify()
  let completed = @async.with_timeout_opt(100, () => wakeup.wait_after(revision))
  assert_true(completed is Some(_))
}

///|
async test "dialog completion wakes only its registered waiter" {
  let completions = DialogCompletionStore()
  @async.with_task_group(group => {
    let waiting = group.spawn(no_wait=true, () => completions.wait(41L))
    while completions.pending.is_empty() {
      @async.pause()
    }
    completions.complete(
      Some(@native.NativeDialogCompletion::{
        dialog: 42L,
        window: Some(7L),
        result: Ok("unrelated"),
      }),
    )
    assert_true(waiting.try_wait() is None)
    completions.complete(
      Some(@native.NativeDialogCompletion::{
        dialog: 41L,
        window: Some(7L),
        result: Ok("selected"),
      }),
    )
    assert_eq(waiting.wait(), "selected")
    group.return_immediately(())
  })
  assert_true(completions.pending.is_empty())
}

///|
async test "dialog completion propagates native failure" {
  let completions = DialogCompletionStore()
  let observed : Ref[@native.NativeError?] = Ref(None)
  @async.with_task_group(group => {
    let waiting = group.spawn(no_wait=true, () => {
      ignore(completions.wait(51L)) catch {
        @native.Status(status~, message~) =>
          observed.val = Some(@native.Status(status~, message~))
        error =>
          abort("unexpected dialog completion error: " + error.to_string())
      }
    })
    while completions.pending.is_empty() {
      @async.pause()
    }
    completions.complete(
      Some(@native.NativeDialogCompletion::{
        dialog: 51L,
        window: None,
        result: Err(@native.Status(status=-7, message="dialog owner closed")),
      }),
    )
    waiting.wait()
    group.return_immediately(())
  })
  assert_eq(
    observed.val,
    Some(@native.Status(status=-7, message="dialog owner closed")),
  )
  assert_true(completions.pending.is_empty())
}

///|
async test "application lifecycle startup rolls back completed hooks" {
  let calls : Array[String] = []
  let cleanup_failures : Array[AppCleanupError] = []
  let configured = html("Lifecycle", "<html></html>")
    .app_lifecycle(
      on_start=fn(_context) {
        calls.push("start:first")
        "first"
      },
      on_shutdown=fn(state) raise {
        calls.push("stop:" + state)
        raise FacadeLifecycleTestError::DestroyFailed(state)
      },
    )
    .app_lifecycle(
      on_start=fn(_context) raise {
        calls.push("start:second")
        raise FacadeLifecycleTestError::StartFailed("second")
      },
      on_shutdown=fn(_state : Unit) { calls.push("unexpected") },
    )
  try {
    @async.with_task_group(group => {
      start_application_lifecycle_hooks(
        configured.application_lifecycle_hooks,
        ApplicationContext(
          group,
          test_window_manager(),
          @locale.LocalePreferences::resolve(None, []),
        ),
        group,
        cleanup_failures,
      )
    })
    fail("expected lifecycle startup failure")
  } catch {
    LifecycleHookError(ApplicationStart(index=1, detail~)) =>
      assert_true(detail.contains("second"))
    _ => fail("expected lifecycle startup failure")
  }
  assert_eq(calls, ["start:first", "start:second", "stop:first"])
  match cleanup_failures {
    [LifecycleHook(ApplicationShutdown(index=0, detail~))] =>
      assert_true(detail.contains("first"))
    _ => fail("expected rollback cleanup failure")
  }
}

///|
async test "window close joins owned tasks before close hooks" {
  let child_stopped = Ref(false)
  let close_saw_stopped = Ref(false)
  let configured = html("Lifecycle", "<html></html>").window_lifecycle(
    on_ready=fn(context) {
      context
      .task_group()
      .spawn_bg(
        () => {
          defer {
            child_stopped.val = true
          }
          @async.sleep(10000)
        },
        no_wait=true,
      )
    },
    on_close=fn(_state) { close_saw_stopped.val = child_stopped.val },
  )
  @async.with_task_group(group => {
    start_window_lifecycle_hooks(
      configured.window_lifecycle_hooks,
      WindowContext(
        "main",
        test_window_handle("main", 17L),
        test_window_manager(),
        group,
        WindowEventEmitter(fn(_route, _name, _payload) {  }),
        @locale.LocalePreferences::resolve(None, []),
      ),
      group,
      [],
    )
    group.return_immediately(())
  })
  assert_true(child_stopped.val)
  assert_true(close_saw_stopped.val)
}

///|
test "command host registers extension dependencies before dependents" {
  let dependency_id = "examples/base"
  let extension_id = "examples/feature"
  let registered : Array[String] = []
  let feature_spec = test_tracking_command_spec(
    extension_id,
    "feature",
    registered,
    dependencies=[dependency_id],
  )
  let dependency_spec = test_tracking_command_spec(
    dependency_id, "base", registered,
  )
  let build = unwrap_app_run(() => {
    test_build_command_host([], [
      test_extension_capability(feature_spec),
      test_extension_capability(dependency_spec),
    ])
  })
  match build.runtime {
    Some(host) => {
      ignore(close_command_host(Some(host)))
      @debug.assert_eq(registered, [dependency_id, extension_id])
    }
    _ => fail("expected command host")
  }
}

///|
test "command host rejects missing extension dependencies" {
  let extension_id = "examples/feature"
  let dependency_id = "examples/base"
  let feature_spec = test_command_spec(extension_id, "feature", [], dependencies=[
    dependency_id,
  ])
  match
    expect_app_run_error(() => {
      test_build_command_host([], [test_extension_capability(feature_spec)])
    }) {
    ConfigurationError(
      ExtensionUnavailable(extension_id=missing_id, requested_by~, state~)
    ) => {
      assert_eq(missing_id, dependency_id)
      assert_eq(requested_by, Some(extension_id))
      assert_eq(state, "missing")
    }
    error => fail(error.message())
  }
}

///|
test "entry HTML injection does not install the bridge" {
  let head_html = "<html><head><title>A</title></head><head></head></html>"
  let injected = inject_html_bootstrap(
    head_html,
    base_tag("proton://app/example/"),
  )
  assert_true(injected.contains("<head>\n<base href="))
  assert_false(injected.contains("<script>"))
  assert_false(injected.contains("__MoonBit__"))
  inspect(injected.contains("</head><head>\n<base"), content="false")
}

///|
test "direct launches use the working directory as their resource directory" {
  let current : @mbpath.Path = "."
  @debug.assert_eq(runtime_resource_dir(), current.resolve().to_string())
}

///|
test "typed facade appends validated secondary windows" {
  let configured = html("Main", "<main>Main</main>").add_window(
    "settings",
    "Settings",
    AppEntry::Html("<main>Settings</main>"),
    width=480,
    height=360,
    size_hint=WindowSizeHint::Fixed,
    open_on_start=false,
  )
  let manifest = configured.inline_manifest()
  assert_eq(manifest.windows.length(), 1)
  assert_eq(manifest.windows[0].id, "settings")
  assert_eq(
    manifest.windows[0].window.size_hint,
    @manifest.WindowSizeHint::Fixed,
  )
  assert_false(manifest.windows[0].open_on_start)
  let plans = planned_windows(manifest)
  assert_eq(plans.map(fn(plan) { plan.id }), ["main", "settings"])
  assert_eq(plans.map(fn(plan) { plan.open_on_start }), [true, false])
}

///|
test "application identity is required and single instance reuses it" {
  let missing = html("App", "<main>App</main>")
  guard missing.validation_error()
    is Some(InvalidSetting(name="identifier", ..)) else {
    fail("expected a missing application identity")
  }
  let invalid = html("App", "<main>App</main>").identifier(" ")
  assert_true(invalid.validation_error() is Some(_))
  let resolved = html("App", "<main>App</main>")
    .identifier("dev.proton.inline")
    .single_instance()
    .resolved_app_config()
  assert_eq(resolved.application_identifier, "dev.proton.inline")
  assert_eq(resolved.instance_identifier, Some("dev.proton.inline"))

  let not_single_instance = html("App", "<main>App</main>")
    .identifier("dev.proton.inline")
    .single_instance(enabled=false)
    .resolved_app_config()
  assert_eq(not_single_instance.instance_identifier, None)
}

///|
test "application identity sources cannot be combined" {
  let app = html("App", "<main>App</main>")
    .identifier("dev.proton.inline")
    .identifier("dev.proton.other")
  assert_true(app.validation_error() is Some(_))

  let managed = html("App", "<main>App</main>")
  managed.application_identity = Some(ProjectConfig("dev.proton.managed"))
  let combined = managed.identifier("dev.proton.inline")
  guard combined.validation_error()
    is Some(InvalidSetting(name="identifier", message~)) else {
    fail("expected duplicate application identity sources")
  }
  assert_true(message.contains("either .load_config() or .identifier(...)"))
}

///|
test "explicit identity must match packaged application metadata" {
  debug_inspect(
    verify_packaged_application_identifier(
      "dev.proton.inline", "dev.proton.inline",
    ),
    content="Ok(\"dev.proton.inline\")",
  )
  guard verify_packaged_application_identifier(
      "dev.proton.inline", "dev.proton.packaged",
    )
    is Err(InvalidSetting(name="identifier", message~)) else {
    fail("expected packaged identity mismatch")
  }
  assert_true(message.contains("dev.proton.packaged"))
}

///|
test "activation associations are declared by application code" {
  let app = html("App", "<main>App</main>")
    .identifier("dev.proton.activation")
    .url_scheme("dev.proton")
    .document_extension(".md")
  let resolved = app.resolved_app_config()
  assert_eq(resolved.url_schemes, ["dev.proton"])
  assert_eq(resolved.document_extensions, ["md"])
}

///|
test "launch activation classifies protocol URLs" {
  assert_true(launch_argument_is_url("dev.proton://open", ["dev.proton"]))
  assert_true(launch_argument_is_url("custom:value", ["custom"]))
  assert_false(launch_argument_is_url("custom:value", ["other"]))
}

///|
test "typed facade rejects duplicate secondary window ids" {
  let configured = html("Main", "<main>Main</main>")
    .add_window("settings", "One", AppEntry::Html("one"))
    .add_window("settings", "Two", AppEntry::Html("two"))
  assert_true(configured.validation_error() is Some(_))
}

///|
test "typed facade reserves the primary window id" {
  let configured = html("Main", "<main>Main</main>").add_window(
    "main",
    "Other",
    AppEntry::Html("other"),
  )
  assert_true(configured.validation_error() is Some(_))
}

///|
async test "notification completion is delivered only to an active waiter" {
  while notification_result_broker.results.length() > 0 {
    ignore(notification_result_broker.results.remove(0))
  }
  notification_result_broker.busy = false
  publish_notification_result(@native.NativeNotificationResult::Delivered)
  assert_eq(notification_result_broker.results.length(), 0)
  acquire_notification_result_slot()
  publish_notification_result(
    @native.NativeNotificationResult::Failed("permission denied"),
  )
  let result = take_notification_result()
  release_notification_result_slot()
  @debug.assert_eq(
    result,
    @native.NativeNotificationResult::Failed("permission denied"),
  )
}

///|
test "notification completion capability controls result waiting" {
  assert_true(notification_result_event_supported(["notification_result"]))
  assert_false(notification_result_event_supported(["runtime_wait"]))
}

///|
test "notification click events use the extension payload contract" {
  inspect(
    notification_click_payload(Some("open-item")).stringify(),
    content="{\"payload\":\"open-item\"}",
  )
  inspect(
    notification_click_payload(None).stringify(),
    content="{\"payload\":null}",
  )
}

///|
/// Normalizes host path separators so path assertions are platform-agnostic.
fn normalize_path_separators(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
test "app data directory follows platform conventions" {
  assert_eq(
    normalize_path_separators(
      app_data_dir_for_platform(
        "macos",
        "com.example.devtoys",
        Some("/Users/test"),
        None,
        None,
      ),
    ),
    "/Users/test/Library/Application Support/com.example.devtoys",
  )
  assert_eq(
    normalize_path_separators(
      app_data_dir_for_platform(
        "linux",
        "com.example.devtoys",
        Some("/home/test"),
        None,
        Some("/data"),
      ),
    ),
    "/data/com.example.devtoys",
  )
  try
    app_data_dir_for_platform(
      "macos",
      "../escape",
      Some("/Users/test"),
      None,
      None,
    )
  catch {
    InvalidIdentifier(_) => ()
    _ => fail("expected invalid identifier")
  } noraise {
    _ => fail("expected invalid identifier")
  }
}

///|
test "application log directory follows platform conventions" {
  assert_eq(
    normalize_path_separators(
      app_log_dir_for_platform(
        "macos",
        "com.example.app",
        Some("/Users/test"),
        None,
        None,
      ),
    ),
    "/Users/test/Library/Logs/com.example.app",
  )
  assert_eq(
    normalize_path_separators(
      app_log_dir_for_platform(
        "windows",
        "com.example.app",
        None,
        Some("C:/Users/test/AppData/Local"),
        None,
      ),
    ),
    "C:/Users/test/AppData/Local/com.example.app/Logs",
  )
  assert_eq(
    normalize_path_separators(
      app_log_dir_for_platform(
        "linux",
        "com.example.app",
        Some("/home/test"),
        None,
        None,
      ),
    ),
    "/home/test/.local/state/com.example.app/logs",
  )
}

///|
test "managed identity reads the packaged identifier" {
  let metadata =
    #|{
    #|  "identifier": "com.example.app",
    #|  "product_name": "Example"
    #|}
  debug_inspect(
    packaged_application_identifier_from_json(metadata),
    content="Ok(\"com.example.app\")",
  )
}

///|
test "managed identity rejects packaged metadata without an identifier" {
  let metadata : Json = { "product_name": "Example" }
  guard packaged_application_identifier_from_json(metadata.stringify())
    is Err(InvalidSetting(message~, ..)) else {
    fail("expected packaged metadata validation to fail")
  }
  inspect(message, content="packaged application metadata requires identifier")
}

///|
fn updater_test_channel(check_on_launch : Bool) -> ResolvedUpdateChannel? {
  url("Test", "https://example.com/")
  .identifier("dev.proton.update-test")
  .update_channel(
    "https://updates.example.com/latest.json",
    ["rsa-sha256:ab:010001"],
    check_on_launch~,
  )
  .resolved_app_config().update_channel
}

///|
test "an update channel is configured by application code" {
  assert_true(updater_test_channel(true) is Some(_))
}

///|
/// Launching contacts the endpoint only when the application is prepared to
/// act on the answer and has not turned the check off.
test "the launch check is opt-in twice over" {
  guard updater_test_channel(true) is Some(enabled) else {
    fail("expected a channel")
  }
  guard updater_test_channel(false) is Some(disabled) else {
    fail("expected a channel")
  }
  assert_true(checks_on_launch(enabled, 1))
  // Declared but nothing registered to act on it: no request is made.
  assert_false(checks_on_launch(enabled, 0))
  // check_on_launch: false wins even when a handler is registered.
  assert_false(checks_on_launch(disabled, 1))
  assert_false(checks_on_launch(disabled, 0))
}

///|
fn test_view_handle(
  id : String,
  native_id : Int64,
  calls : Array[String],
) -> ViewHandle {
  ViewHandle::{
    id,
    native_id,
    set_view_bounds: fn(x, y, width, height) {
      calls.push("set_bounds:\{x},\{y},\{width},\{height}")
    },
    set_view_visible: fn(visible) { calls.push("set_visible:\{visible}") },
    set_view_z_order: fn(z_order) { calls.push("set_z_order:\{z_order}") },
    load_view_url: fn(url) { calls.push("load_url:\{url}") },
    load_view_html: fn(_html, _base_url) {  },
    eval_view_script: fn(_script) {  },
    send_view_command: fn(_command, _download_id) {  },
    read_view_state: fn() {
      { x: 1, y: 2, width: 300, height: 200, visible: true, z_order: 1, }
    },
    close_view: fn() { calls.push("close") },
  }
}

///|
test "view handle routes operations through its closures" {
  let calls : Array[String] = []
  let view = test_view_handle("panel", 7L, calls)
  inspect(view.id(), content="panel")
  view.set_bounds(x=1, y=2, width=300, height=200)
  view.set_visible(false)
  view.set_z_order(2)
  view.load_url("https://example.com/")
  let state = view.state()
  inspect(state.width, content="300")
  inspect(state.z_order, content="1")
  view.close()
  debug_inspect(
    calls,
    content=(
      #|[
      #|  "set_bounds:1,2,300,200",
      #|  "set_visible:false",
      #|  "set_z_order:2",
      #|  "load_url:https://example.com/",
      #|  "close",
      #|]
    ),
  )
}

///|
test "window context menu routes through the public window handle" {
  let calls : Array[String] = []
  let window = test_window_handle("main", 17L, popup_calls=calls)
  let menu = Menu("Context", items=[MenuItem::separator()])
  menu.popup(window, 123, 456)
  debug_inspect(calls, content="[\"popup:Context@123,456\"]")
}

///|
test "window content size routes logical dimensions through the handle" {
  let calls : Array[(Int, Int)] = []
  let window = test_window_handle(
    "main",
    17L,
    content_size_calls=calls,
    content_size=(640, 360),
  )
  window.set_content_size(800, 450)
  inspect(window.content_size(), content="(640, 360)")
  inspect(calls, content="[(800, 450)]")
}

///|
test "window progress routes Electron-compatible values through the handle" {
  let calls : Array[Double] = []
  let window = test_window_handle("main", 17L, progress_calls=calls)
  window.set_progress_bar(0.42)
  window.set_progress_bar(2.0)
  window.set_progress_bar(-1.0)
  debug_inspect(calls, content="[0.42, 2, -1]")
}

///|
test "window attention routes Electron-compatible flags through the handle" {
  let calls : Array[Bool] = []
  let window = test_window_handle("main", 17L, flash_calls=calls)
  window.flash_frame(true)
  window.flash_frame(false)
  debug_inspect(calls, content="[true, false]")
}

///|
test "window resizable routes live capability changes through the handle" {
  let calls : Array[Bool] = []
  let window = test_window_handle("main", 17L, resizable_calls=calls)
  window.set_resizable(false)
  window.set_resizable(true)
  debug_inspect(calls, content="[false, true]")
}

///|
test "window movable routes live capability changes through the handle" {
  let calls : Array[Bool] = []
  let window = test_window_handle("main", 17L, movable_calls=calls)
  window.set_movable(false)
  window.set_movable(true)
  debug_inspect(calls, content="[false, true]")
}

///|
test "window opacity routes live values through the handle" {
  let calls : Array[Double] = []
  let window = test_window_handle("main", 17L, opacity_calls=calls)
  window.set_opacity(0.35)
  window.set_opacity(1.0)
  debug_inspect(calls, content="[0.35, 1]")
}

///|
test "window taskbar visibility routes live flags through the handle" {
  let calls : Array[Bool] = []
  let window = test_window_handle("main", 17L, skip_taskbar_calls=calls)
  window.set_skip_taskbar(true)
  window.set_skip_taskbar(false)
  debug_inspect(calls, content="[true, false]")
}

///|
test "window content protection routes live flags through the handle" {
  let calls : Array[Bool] = []
  let window = test_window_handle("main", 17L, content_protection_calls=calls)
  window.set_content_protection(true)
  window.set_content_protection(false)
  debug_inspect(calls, content="[true, false]")
}

///|
test "window minimizable routes live flags through the handle" {
  let calls : Array[Bool] = []
  let window = test_window_handle("main", 17L, minimizable_calls=calls)
  window.set_minimizable(false)
  window.set_minimizable(true)
  debug_inspect(calls, content="[false, true]")
}

///|
test "window maximizable routes live flags through the handle" {
  let calls : Array[Bool] = []
  let window = test_window_handle("main", 17L, maximizable_calls=calls)
  window.set_maximizable(false)
  window.set_maximizable(true)
  debug_inspect(calls, content="[false, true]")
}

///|
test "window closable routes live flags through the handle" {
  let calls : Array[Bool] = []
  let window = test_window_handle("main", 17L, closable_calls=calls)
  window.set_closable(false)
  window.set_closable(true)
  debug_inspect(calls, content="[false, true]")
}

///|
test "window focusable routes live flags through the handle" {
  let calls : Array[Bool] = []
  let window = test_window_handle("main", 17L, focusable_calls=calls)
  window.set_focusable(false)
  window.set_focusable(true)
  debug_inspect(calls, content="[false, true]")
}

///|
test "window fullscreenable routes live flags through the handle" {
  let calls : Array[Bool] = []
  let window = test_window_handle("main", 17L, fullscreenable_calls=calls)
  window.set_fullscreenable(false)
  window.set_fullscreenable(true)
  debug_inspect(calls, content="[false, true]")
}

///|
test "window shadow routes live flags through the handle" {
  let calls : Array[Bool] = []
  let window = test_window_handle("main", 17L, has_shadow_calls=calls)
  window.set_has_shadow(false)
  window.set_has_shadow(true)
  debug_inspect(calls, content="[false, true]")
}

///|
test "window mouse event handling routes flags through the handle" {
  let calls : Array[(Bool, Bool)] = []
  let window = test_window_handle("main", 17L, ignore_mouse_events_calls=calls)
  window.set_ignore_mouse_events(true, true)
  window.set_ignore_mouse_events(false, true)
  debug_inspect(calls, content="[(true, true), (false, true)]")
}

///|
test "window background color routes values through the handle" {
  let calls : Array[String] = []
  let window = test_window_handle("main", 17L, background_color_calls=calls)
  window.set_background_color("#112233")
  debug_inspect(calls, content="[\"#112233\"]")
}

///|
test "window kiosk routes live flags through the handle" {
  let calls : Array[Bool] = []
  let window = test_window_handle("main", 17L, kiosk_calls=calls)
  window.set_kiosk(true)
  window.set_kiosk(false)
  debug_inspect(calls, content="[true, false]")
}

///|
test "window workspace visibility routes live flags through the handle" {
  let calls : Array[Bool] = []
  let window = test_window_handle(
    "main",
    17L,
    visible_on_all_workspaces_calls=calls,
  )
  window.set_visible_on_all_workspaces(true)
  window.set_visible_on_all_workspaces(false)
  debug_inspect(calls, content="[true, false]")
}

///|
test "window enabled routes live flags through the handle" {
  let calls : Array[Bool] = []
  let window = test_window_handle("main", 17L, enabled_calls=calls)
  window.set_enabled(false)
  window.set_enabled(true)
  debug_inspect(calls, content="[false, true]")
}

///|
test "window aspect ratio routes live values through the handle" {
  let calls : Array[Double] = []
  let window = test_window_handle("main", 17L, aspect_ratio_calls=calls)
  window.set_aspect_ratio(16.0 / 9.0)
  window.set_aspect_ratio(0.0)
  debug_inspect(calls, content="[1.7777777777777777, 0]")
}

///|
test "window center uses the current monitor work area and frame size" {
  let position_calls : Array[(Int, Int)] = []
  let window = test_window_handle("main", 17L, position_calls~, window_state=WindowState::{
    x: 120,
    y: 80,
    width: 800,
    height: 600,
    monitor: WindowMonitor::{
      x: 0,
      y: 0,
      width: 1920,
      height: 1080,
      work_x: 0,
      work_y: 24,
      work_width: 1920,
      work_height: 1032,
      scale_factor_percent: 100,
    },
    zoom_percent: 100,
    visible: true,
    focused: true,
    minimized: false,
    maximized: false,
    fullscreen: false,
    always_on_top: false,
    theme: "system",
  })
  window.center()
  debug_inspect(position_calls, content="[(560, 240)]")
}

///|
test "window bounds read and write use Electron coordinate order" {
  let position_calls : Array[(Int, Int)] = []
  let size_calls : Array[(Int, Int)] = []
  let window = test_window_handle("main", 17L, position_calls~, size_calls~, window_state=WindowState::{
    x: 120,
    y: 80,
    width: 800,
    height: 600,
    monitor: WindowMonitor::{
      x: 0,
      y: 0,
      width: 1920,
      height: 1080,
      work_x: 0,
      work_y: 0,
      work_width: 1920,
      work_height: 1080,
      scale_factor_percent: 100,
    },
    zoom_percent: 100,
    visible: true,
    focused: true,
    minimized: false,
    maximized: false,
    fullscreen: false,
    always_on_top: false,
    theme: "system",
  })
  assert_eq(window.bounds(), (120, 80, 800, 600))
  window.set_bounds(x=40, y=50, width=640, height=480)
  debug_inspect(position_calls, content="[(40, 50)]")
  debug_inspect(size_calls, content="[(640, 480)]")
}

///|
test "window size limits route live constraints through the handle" {
  let minimum_calls : Array[(Int, Int)] = []
  let maximum_calls : Array[(Int, Int)] = []
  let window = test_window_handle(
    "main",
    17L,
    minimum_size_calls=minimum_calls,
    maximum_size_calls=maximum_calls,
  )
  window.set_minimum_size(640, 480)
  window.set_minimum_size(0, 0)
  window.set_maximum_size(1280, 900)
  window.set_maximum_size(0, 0)
  debug_inspect(minimum_calls, content="[(640, 480), (0, 0)]")
  debug_inspect(maximum_calls, content="[(1280, 900), (0, 0)]")
}

///|
test "with_view stores declarative views and rejects invalid ids" {
  let app = html("Test", "<html></html>")
  inspect(app.planned_views.length(), content="0")
  let app = app.with_view(
    "browser",
    ViewConfig(width=320, height=240, initial_url="about:blank"),
  )
  inspect(app.planned_views.length(), content="1")
  let app = app.with_view("browser", ViewConfig(width=1, height=1))
  let app = app.with_view("  ", ViewConfig(width=1, height=1))
  inspect(app.planned_views.length(), content="1")
  inspect(app.validation_errors.length(), content="2")
}

///|
async test "lifecycle contexts expose one immutable locale snapshot" {
  let preferences = @locale.LocalePreferences::resolve(
    Some(@locale.Locale::parse("zh-CN")),
    [@locale.Locale::parse("en-GB")],
  )
  @async.with_task_group(group => {
    let application = ApplicationContext(
      group,
      test_window_manager(),
      preferences,
    )
    assert_eq(application.locale().to_string(), "zh-CN")
    assert_eq(
      application.preferred_languages().map(locale => locale.to_string()),
      ["zh-CN", "en-GB", "en-US"],
    )
    let window = WindowContext(
      "main",
      test_window_handle("main", 17L),
      test_window_manager(),
      group,
      WindowEventEmitter(fn(_route, _name, _payload) {  }),
      preferences,
    )
    assert_eq(window.locale(), application.locale())
    assert_eq(window.preferred_languages(), application.preferred_languages())
    group.return_immediately(())
  })
}

///|
test "standard menus resolve from the application locale" {
  let preferences = @locale.LocalePreferences::resolve(
    Some(@locale.Locale::parse("zh-CN")),
    [],
  )
  let resolved = resolve_menu(
    @native.MenuBar(menus=[
      @native.Menu::role(@native.MenuRole::Edit),
      @native.Menu::role(@native.MenuRole::Window),
    ]),
    preferences,
    "Proton Demo",
    macos_application_menu=true,
  )
  let definitions = resolved.definitions()
  assert_eq(definitions.length(), 3)
  let (application_role, application_label, application_items) = definitions[0].definition()
  assert_eq(application_role, Some(@native.MenuRole::Application))
  assert_eq(application_label, Some("Proton Demo"))
  let application_items = application_items.unwrap()
  let (_, _, quit_label, quit_key, quit_role, _) = application_items[application_items.length() -
  1].definition()
  assert_eq(quit_role, Some(@native.MenuItemRole::Quit))
  assert_eq(quit_label, Some("退出 Proton Demo"))
  assert_eq(quit_key, Some("q"))
  let (edit_role, edit_label, edit_items) = definitions[1].definition()
  assert_eq(edit_role, Some(@native.MenuRole::Edit))
  assert_eq(edit_label, Some("编辑"))
  let edit_items = edit_items.unwrap()
  let (_, _, copy_label, copy_key, copy_role, _) = edit_items[4].definition()
  assert_eq(copy_role, Some(@native.MenuItemRole::Copy))
  assert_eq(copy_label, Some("拷贝"))
  assert_eq(copy_key, Some("c"))
  let (window_role, window_label, _) = definitions[2].definition()
  assert_eq(window_role, Some(@native.MenuRole::Window))
  assert_eq(window_label, Some("窗口"))
}

///|
test "runtime menu defaults are platform-specific" {
  let preferences = @locale.LocalePreferences::resolve(
    Some(@locale.Locale::parse("en-US")),
    [],
  )
  assert_eq(
    resolve_runtime_menu(None, preferences, "Proton Demo", platform="linux"),
    None,
  )
  let macos = resolve_runtime_menu(
    None,
    preferences,
    "Proton Demo",
    platform="macos",
  ).unwrap()
  let (role, _, _) = macos.definitions()[0].definition()
  assert_eq(role, Some(@native.MenuRole::Application))
}

///|
test "custom menu labels never imply a standard role" {
  let preferences = @locale.LocalePreferences::resolve(
    Some(@locale.Locale::parse("en-US")),
    [],
  )
  let resolved = resolve_menu(
    @native.MenuBar(menus=[
      @native.Menu("Edit", items=[
        @native.MenuItem::command("custom.edit", "Custom Edit"),
      ]),
    ]),
    preferences,
    "Proton Demo",
  )
  let definitions = resolved.definitions()
  assert_eq(definitions.length(), 1)
  let (role, label, items) = definitions[0].definition()
  assert_eq(role, None)
  assert_eq(label, Some("Edit"))
  let (_, command_id, command_label, _, item_role, _) = items.unwrap()[0].definition()
  assert_eq(command_id, Some("custom.edit"))
  assert_eq(command_label, Some("Custom Edit"))
  assert_eq(item_role, None)
}

///|
test "explicit standard menu items replace role defaults" {
  let preferences = @locale.LocalePreferences::resolve(
    Some(@locale.Locale::parse("en-US")),
    [],
  )
  let resolved = resolve_menu(
    @native.MenuBar(menus=[@native.Menu::role(@native.MenuRole::Edit, items=[])]),
    preferences,
    "Proton Demo",
  )
  let (_, _, items) = resolved.definitions()[0].definition()
  assert_eq(items.unwrap(), [])
}

///|
test "macOS menu resolution puts an explicit application role first" {
  let preferences = @locale.LocalePreferences::resolve(
    Some(@locale.Locale::parse("en-US")),
    [],
  )
  let resolved = resolve_menu(
    @native.MenuBar(menus=[
      @native.Menu::role(@native.MenuRole::Edit),
      @native.Menu::role(@native.MenuRole::Application),
      @native.Menu::role(@native.MenuRole::Window),
    ]),
    preferences,
    "Proton Demo",
    macos_application_menu=true,
  )
  let definitions = resolved.definitions()
  let (first_role, _, _) = definitions[0].definition()
  let (second_role, _, _) = definitions[1].definition()
  let (third_role, _, _) = definitions[2].definition()
  assert_eq(first_role, Some(@native.MenuRole::Application))
  assert_eq(second_role, Some(@native.MenuRole::Edit))
  assert_eq(third_role, Some(@native.MenuRole::Window))
}

///|
test "framework catalog localizes controls without changing technical details" {
  let detail = "Error code: bridge_bootstrap_failed\nPath: /tmp/app"
  let chinese = @locale.LocalePreferences::resolve(
    Some(@locale.Locale::parse("zh-CN")),
    [],
  )
  let chinese_catalog = framework_catalog(chinese)
  assert_eq(chinese_catalog.dialog_ok, "确定")
  assert_eq(chinese_catalog.dialog_cancel, "取消")
  assert_eq(chinese_catalog.titlebar_restore, "还原")
  assert_eq(startup_failure_title(chinese), "应用启动失败")
  assert_eq(
    framework_failure_message(startup_failure_summary(chinese), detail),
    "应用无法启动。\n\n" + detail,
  )
  assert_eq(application_error_title(chinese), "应用错误")
  assert_eq(
    framework_failure_message(application_error_summary(chinese), detail),
    "应用遇到错误。\n\n" + detail,
  )
  let unsupported = @locale.LocalePreferences::resolve(
    Some(@locale.Locale::parse("fr-FR")),
    [],
  )
  let fallback_catalog = framework_catalog(unsupported)
  assert_eq(fallback_catalog.dialog_ok, "OK")
  assert_eq(fallback_catalog.titlebar_close, "Close")
  assert_eq(startup_failure_title(unsupported), "Application Startup Failed")
  assert_eq(
    framework_failure_message(startup_failure_summary(unsupported), detail),
    "The application could not start.\n\n" + detail,
  )
  assert_eq(application_error_title(unsupported), "Application Error")
  assert_eq(
    framework_failure_message(application_error_summary(unsupported), detail),
    "The application encountered an error.\n\n" + detail,
  )
}

///|
test "system locale errors expose stable facade diagnostics" {
  let error = SystemLocaleError::NativeQuery(status=-9, detail="query failed")
  assert_eq(
    error.message(),
    "failed to query system preferred languages (-9): query failed",
  )
}

///|
test "POSIX system locales are normalized only on Linux" {
  assert_eq(
    normalize_platform_languages(["zh_CN.UTF-8"], posix=true).map(locale => {
      locale.to_string()
    }),
    ["zh-CN"],
  )
  assert_eq(
    normalize_platform_languages(["en-US"], posix=false).map(locale => {
      locale.to_string()
    }),
    ["en-US"],
  )
}
