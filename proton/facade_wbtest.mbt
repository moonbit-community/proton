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
  @async.sleep(0) catch {
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
fn test_window_handle(id : String, native_id : Int64) -> WindowHandle {
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
    set_window_size: fn(_width, _height) {  },
    minimize_window: fn() {  },
    maximize_window: fn() {  },
    restore_window: fn() {  },
    set_window_fullscreen: fn(_fullscreen) {  },
    set_window_position: fn(_x, _y) {  },
    set_window_always_on_top: fn(_always_on_top) {  },
    set_window_zoom_percent: fn(_zoom_percent) {  },
    read_window_state: fn() { abort("test window state is not available") },
    browser,
    add_view: fn(_id, _config) { abort("test views are not available") },
    remove_view: fn(_id) { abort("test views are not available") },
    list_views: fn() { [] },
    find_view: fn(_id) { None },
  }
}

///|
fn test_command_manifest(
  extension_id : String,
  enabled? : Bool = true,
) -> @manifest.AppManifest {
  let setting = if enabled {
    @manifest.ExtensionSetting::enabled()
  } else {
    @manifest.ExtensionSetting::disabled()
  }
  let extensions : Map[String, @manifest.ExtensionSetting] = Map([])
  extensions[extension_id] = setting
  @manifest.AppManifest::new(
    @manifest.WindowManifest::new("Test", 320, 240),
    @manifest.AppEntry::Html("<html></html>"),
    extensions~,
  )
}

///|
fn test_command_manifest_ids(
  extension_ids : Array[String],
) -> @manifest.AppManifest {
  let extensions : Map[String, @manifest.ExtensionSetting] = Map([])
  for id in extension_ids {
    extensions[id] = @manifest.ExtensionSetting::enabled()
  }
  @manifest.AppManifest::new(
    @manifest.WindowManifest::new("Test", 320, 240),
    @manifest.AppEntry::Html("<html></html>"),
    extensions~,
  )
}

///|
fn test_command_spec(
  extension_id : String,
  js_namespace : String,
  api_names : Array[String],
  dependencies? : Array[String] = [],
  scripts? : Array[String] = [],
  resolve_permission? : (Json, String) -> Json raise @proton_command.PermissionScopeValidationError,
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
  let diagnostic = @native.BridgeDiagnostic::{
    abi_version: 1,
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
async test "app run requires Proton's event loop" {
  let mut rejected = false
  html("Test", "<html></html>").run() catch {
    RunnerError(message) => {
      rejected = true
      assert_true(message.contains("@proton.install_event_loop"))
      assert_true(message.contains("async fn main"))
    }
    error => fail("expected runner error, got " + @debug.render(Repr(error)))
  }
  assert_true(rejected)
}

///|
test "bridge startup timeout is finite and configurable" {
  let default_app = html("Test", "<html></html>")
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
test "headless mode defaults off and is configurable" {
  let default_app = html("Test", "<html></html>")
  assert_false(default_app.headless_value)
  assert_true(default_app.headless().headless_value)
  assert_false(default_app.headless(enabled=false).headless_value)
}

///|
test "PROTON_HEADLESS forces facade headless mode" {
  let old_headless = @env.get_env_var("PROTON_HEADLESS")
  defer restore_env_var("PROTON_HEADLESS", old_headless)
  let app = html("Test", "<html></html>")
  @env.unset_env_var("PROTON_HEADLESS")
  assert_false(app.resolved_headless())
  @env.set_env_var("PROTON_HEADLESS", "1")
  assert_true(app.resolved_headless())
  @env.set_env_var("PROTON_HEADLESS", "off")
  assert_false(app.resolved_headless())
  assert_true(app.headless().resolved_headless())
}

///|
async test "headless mode rejects titlebar overlay before runtime startup" {
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new(
      "Test",
      320,
      240,
      titlebar_style=@manifest.TitlebarStyle::Overlay,
    ),
    @manifest.AppEntry::Html("<html></html>"),
  )
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  let mut rejected = false
  run_manifest(manifest, ".", command_extensions, [], [], [], None, 30000, true) catch {
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
  let manifest = test_command_manifest("test/disabled", enabled=false)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  let menu = @native.MenuBar::new(menus=[
    @native.Menu::new("App", items=[
      @native.MenuItem::role("close", label="Close"),
    ]),
  ])
  let mut rejected = false
  run_manifest(
    manifest,
    ".",
    command_extensions,
    [],
    [],
    [],
    Some(menu),
    30000,
    true,
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
async test "startup dispatch retains an earlier window close" {
  let runtime = @native.Runtime::new()
  let first = @native.Window::new(runtime)
  let second = @native.Window::new(runtime)
  defer {
    first.destroy() catch {
      _ => ()
    }
    second.destroy() catch {
      _ => ()
    }
    runtime.destroy() catch {
      _ => ()
    }
  }
  while runtime.poll_event() is Some(_) {

  }
  let windows = [
    RunningWindow::{
      id: "main",
      window: first,
      permissions: WindowPermissionPolicy::{ grants: [] },
      lifetime: WindowLifetime::new(),
      views: [],
      bridge_ready: true,
      state: WindowOpen,
    },
    RunningWindow::{
      id: "secondary",
      window: second,
      permissions: WindowPermissionPolicy::{ grants: [] },
      lifetime: WindowLifetime::new(),
      views: [],
      bridge_ready: false,
      state: WindowStarting,
    },
  ]
  @async.with_task_group(group => {
    let task = group.spawn(
      () => {
        @async.sleep(10000)
        @native.BridgeResponse::Ok(request_id=42L, payload=null)
      },
      no_wait=true,
      allow_failure=true,
    )
    let pending = [
      BridgeDispatchTask::{
        request_id: 42L,
        window: second.id(),
        task,
        state: Running,
      },
    ]
    first.close()
    match runtime.poll_event() {
      Some(event) =>
        runtime_session_dispatch_window_event(windows, pending, event)
      None => fail("expected the first window close event")
    }
    assert_eq(pending.length(), 1)
    assert_true(pending[0].state is Running)
    runtime_session_cancel_all_bridge_tasks(pending)
    group.return_immediately(())
  })
  assert_true(windows[0].is_closed())
  assert_true(windows[0].lifetime.closed)
  assert_false(windows[1].is_closed())
  assert_false(windows[1].lifetime.closed)
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
  let event = @ipc.IpcExtensionEvent::new("ticker", "tick", {
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
  let file_path = resolve_entry_path(path)
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
test "extension event transport can target a page instance" {
  let event = @ipc.IpcExtensionEvent::new("ticker", "done", null)
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
    @native.BridgeGrantConfig::new("http://localhost:3000", ops=["app:ping"]),
  ]).to_json_string()
  let second = native_bridge_config([
    @native.BridgeGrantConfig::new("http://localhost:4000", ops=["app:ping"]),
  ]).to_json_string()
  assert_true(first.contains("http://localhost:3000"))
  assert_false(first.contains("http://localhost:4000"))
  assert_true(second.contains("http://localhost:4000"))
  assert_false(second.contains("http://localhost:3000"))
  assert_false(first.contains("request_timeout_ms"))
  assert_false(second.contains("request_timeout_ms"))
}

///|
test "HTTP entry permissions use the exact canonical origin" {
  let policy = unwrap_configuration(() => {
    bridge_page_policy_for_entry(
      @manifest.AppEntry::Url("HTTPS://Example.COM:443/app"),
    )
  })
  assert_eq(policy.entry_origin, Some("https://example.com"))
}

///|
test "replacing a development entry preserves permission grants" {
  let original = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("Development", 320, 240),
    @manifest.AppEntry::Asset("app.html"),
    permissions=[
      @manifest.PermissionGrant::new(
        "main",
        @manifest.PermissionOrigin::Entry,
        "app",
      ),
    ],
  )
  let replaced = manifest_with_entry(
    original,
    @manifest.AppEntry::Url("http://localhost:5173"),
  )
  let grants = replaced.permission_grants()
  assert_eq(grants.length(), 1)
  assert_eq(grants[0].extension(), "app")
}

///|
test "permission policy binds extension ops and scope to one trusted source" {
  let extension_id = "examples/scoped"
  let extensions : Map[String, @manifest.ExtensionSetting] = Map([])
  extensions[extension_id] = @manifest.ExtensionSetting::enabled()
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("Scoped", 320, 240),
    @manifest.AppEntry::Html("<html></html>"),
    extensions~,
    permissions=[
      @manifest.PermissionGrant::new(
        "main",
        @manifest.PermissionOrigin::Entry,
        extension_id,
        scope={ "root": "./data" },
      ),
    ],
  )
  let specs : Map[String, @proton_command.AppCommandExtensionSpec] = Map([])
  specs[extension_id] = test_command_spec(extension_id, "scoped", ["read"], resolve_permission=fn(
    scope,
    base_path,
  ) {
    { "base_path": base_path, "scope": scope }
  })
  let policy = unwrap_configuration(() => {
    resolve_window_permission_policy(
      "main",
      BridgePagePolicy::{ entry_origin: None },
      manifest,
      "/trusted/project",
      specs,
      ["ext:scoped/read"],
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
test "registered renderer capabilities require an explicit grant" {
  let extension_id = "examples/ungranted"
  let manifest = test_command_manifest(extension_id)
  let specs : Map[String, @proton_command.AppCommandExtensionSpec] = Map([])
  specs[extension_id] = test_command_spec(extension_id, "ungranted", ["read"])
  match
    expect_configuration_error(() => {
      validate_registered_capabilities_have_grants(manifest, specs, [
        "ext:ungranted/read",
      ])
    }) {
    MissingPermissionGrant(extension_id=actual) =>
      assert_eq(actual, extension_id)
    error => fail(error.message())
  }
}

///|
test "permission grants reject unknown windows" {
  let extension_id = "examples/window"
  let extensions : Map[String, @manifest.ExtensionSetting] = Map([])
  extensions[extension_id] = @manifest.ExtensionSetting::enabled()
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("Unknown window", 320, 240),
    @manifest.AppEntry::Html("<html></html>"),
    extensions~,
    permissions=[
      @manifest.PermissionGrant::new(
        "missing",
        @manifest.PermissionOrigin::Entry,
        extension_id,
      ),
    ],
  )
  let specs : Map[String, @proton_command.AppCommandExtensionSpec] = Map([])
  specs[extension_id] = test_command_spec(extension_id, "window", ["read"])
  match
    expect_configuration_error(() => {
      validate_registered_capabilities_have_grants(manifest, specs, [
        "ext:window/read",
      ])
    }) {
    InvalidPermissionGrant(detail~) =>
      assert_true(detail.contains("unknown window missing"))
    error => fail(error.message())
  }
}

///|
test "extension permission scopes are validated before startup" {
  let extension_id = "examples/unscoped"
  let extensions : Map[String, @manifest.ExtensionSetting] = Map([])
  extensions[extension_id] = @manifest.ExtensionSetting::enabled()
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("Invalid scope", 320, 240),
    @manifest.AppEntry::Html("<html></html>"),
    extensions~,
    permissions=[
      @manifest.PermissionGrant::new(
        "main",
        @manifest.PermissionOrigin::Entry,
        extension_id,
        scope={ "unexpected": true },
      ),
    ],
  )
  let specs : Map[String, @proton_command.AppCommandExtensionSpec] = Map([])
  specs[extension_id] = test_command_spec(extension_id, "unscoped", ["read"])
  match
    expect_configuration_error(() => {
      ignore(
        resolve_window_permission_policy(
          "main",
          BridgePagePolicy::{ entry_origin: None },
          manifest,
          "/trusted/project",
          specs,
          ["ext:unscoped/read"],
        ),
      )
    }) {
    InvalidPermissionGrant(detail~) =>
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
  let manifest = test_command_manifest(extension_id)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  let contract = @proton_contract.extension(
    id=extension_id,
    js_namespace="destroyTest",
  )
  let ping : @proton_contract.Command[Unit, String] = contract.command("ping")
  command_extensions[extension_id] = @proton_command.AppCommandExtensionSpec::typed(
    contract,
    [ping.contract_route()],
    fn(registrar) raise { registrar.bind(ping, (_context, _request) => "pong") },
    on_destroy=fn() { destroyed.val = destroyed.val + 1 },
  ) catch {
    error => abort(error.message())
  }
  match unwrap_app_run(() => build_command_host(manifest, command_extensions)) {
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
test "command host installs typed application registrars before sealing" {
  let manifest = test_command_manifest_ids([])
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  let ping : @proton_contract.Command[Unit, String] = @proton_contract.command(
    "ping",
  )
  let registrars : Array[(@proton_command.CommandRegistrar) -> Unit raise] = [
    registrar => registrar.bind(ping, (_context, _request) => "pong"),
  ]
  match
    unwrap_app_run(() => {
      build_command_host(
        manifest,
        command_extensions,
        command_registrars=registrars,
      )
    }) {
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
  let manifest = test_command_manifest_ids([base_id, feature_id])
  let destroyed : Array[String] = []
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  command_extensions[base_id] = @proton_command.AppCommandExtensionSpec::typed(
    @proton_contract.extension(id=base_id, js_namespace="baseDestroy"),
    [],
    fn(_registrar) {  },
    on_destroy=fn() { destroyed.push(base_id) },
  ) catch {
    error => abort(error.message())
  }
  command_extensions[feature_id] = @proton_command.AppCommandExtensionSpec::typed(
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
  match unwrap_app_run(() => build_command_host(manifest, command_extensions)) {
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
  let manifest = test_command_manifest(extension_id)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  command_extensions[extension_id] = @proton_command.AppCommandExtensionSpec::typed(
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
    ignore(build_command_host(manifest, command_extensions))
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
  let lifecycle = AppLifecycle::new()
  assert_true(lifecycle.state is Constructing)
  lifecycle.begin_starting()
  lifecycle.begin_running()
  assert_true(lifecycle.state is Running)
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
      ApplicationContext::new(group, test_window_manager()),
      group,
      [],
    )
    group.return_immediately(())
  })
  assert_eq(calls, ["start:first", "start:second", "stop:second", "stop:first"])
}

///|
async test "runtime wakeup preserves notification before suspension" {
  let wakeup = RuntimeWakeup::{ signal: @core.RuntimeWakeSignal::new() }
  let revision = wakeup.revision()
  wakeup.signal.notify()
  let completed = @async.with_timeout_opt(100, () => wakeup.wait_after(revision))
  assert_true(completed is Some(_))
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
        ApplicationContext::new(group, test_window_manager()),
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
      WindowContext::new(
        "main",
        @native.WindowRef::unsafe_from_handle(17L),
        test_window_handle("main", 17L),
        test_window_manager(),
        group,
        WindowEventEmitter::new(fn(_route, _name, _payload) {  }),
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
  let manifest = test_command_manifest_ids([dependency_id, extension_id])
  let registered : Array[String] = []
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  command_extensions[extension_id] = test_tracking_command_spec(
    extension_id,
    "feature",
    registered,
    dependencies=[dependency_id],
  )
  command_extensions[dependency_id] = test_tracking_command_spec(
    dependency_id, "base", registered,
  )
  match unwrap_app_run(() => build_command_host(manifest, command_extensions)) {
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
  let manifest = test_command_manifest(extension_id)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  command_extensions[extension_id] = test_command_spec(
    extension_id,
    "feature",
    [],
    dependencies=[dependency_id],
  )
  match
    expect_app_run_error(() => build_command_host(manifest, command_extensions)) {
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
fn write_facade_dev_config(path : String, dev_url? : String) -> Unit {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir("target/proton-facade-dev") catch {
    _ => ()
  }
  let config : Json = {
    "window": { "title": "Dev Test", "width": 320, "height": 240 },
    "entry": { "kind": "asset", "value": "app.html" },
    "debug": true,
  }
  guard config is Object(fields) else {
    abort("expected project config object")
  }
  match dev_url {
    Some(url) => fields["frontend"] = { "dev_url": url }
    None => ()
  }
  @mbfs.write_string_to_file(
    path,
    Json::object(fields).stringify(indent=2) + "\n",
    encoding="utf8",
  ) catch {
    err => abort(@debug.render(Repr(err)))
  }
}

///|
fn restore_env_var(name : String, value : String?) -> Unit {
  match value {
    Some(value) => @env.set_env_var(name, value)
    None => @env.unset_env_var(name)
  }
}

///|
test "implicit config path honors PROTON_CONFIG_PATH" {
  let config_path = "target/proton-facade-dev/implicit-env.proton.project.json"
  write_facade_dev_config(config_path)
  let old_config = @env.get_env_var("PROTON_CONFIG_PATH")
  defer restore_env_var("PROTON_CONFIG_PATH", old_config)

  @env.set_env_var("PROTON_CONFIG_PATH", config_path)
  @debug.assert_eq(implicit_config_path(), Some(config_path))
}

///|
test "packaged config takes precedence over environment and working directory" {
  @debug.assert_eq(
    choose_implicit_config_path(
      bundled=Some(
        "/Applications/Todo.app/Contents/Resources/proton.project.json",
      ),
      environment=Some("/tmp/override.proton.project.json"),
      cwd_has_default=true,
    ),
    Some("/Applications/Todo.app/Contents/Resources/proton.project.json"),
  )
}

///|
test "default config API honors PROTON_CONFIG_PATH" {
  let config_path = "target/proton-facade-dev/config-api-env.proton.project.json"
  write_facade_dev_config(config_path)
  let old_config = @env.get_env_var("PROTON_CONFIG_PATH")
  let old_dev = @env.get_env_var("PROTON_DEV")
  let old_mode = @env.get_env_var("PROTON_MODE")
  defer restore_env_var("PROTON_MODE", old_mode)
  defer restore_env_var("PROTON_DEV", old_dev)
  defer restore_env_var("PROTON_CONFIG_PATH", old_config)

  @env.set_env_var("PROTON_CONFIG_PATH", config_path)
  @env.unset_env_var("PROTON_DEV")
  @env.unset_env_var("PROTON_MODE")
  let app = config("proton.project.json")
  @debug.assert_eq(app.file_path, Some(config_path))
  let resolved = unwrap_configuration(() => app.resolved_app_config())
  assert_eq(resolved.manifest.window.title, "Dev Test")
}

///|
test "config API keeps non-default paths explicit" {
  let config_path = "target/proton-facade-dev/explicit.proton.project.json"
  let env_path = "target/proton-facade-dev/explicit-env.proton.project.json"
  write_facade_dev_config(config_path)
  write_facade_dev_config(env_path)
  let old_config = @env.get_env_var("PROTON_CONFIG_PATH")
  defer restore_env_var("PROTON_CONFIG_PATH", old_config)

  @env.set_env_var("PROTON_CONFIG_PATH", env_path)
  @debug.assert_eq(config(config_path).file_path, Some(config_path))
}

///|
test "config API overrides manifest fields and keeps base dir" {
  let config_path = "target/proton-facade-dev/api-overrides.proton.project.json"
  write_facade_dev_config(config_path)
  let old_dev = @env.get_env_var("PROTON_DEV")
  let old_mode = @env.get_env_var("PROTON_MODE")
  defer restore_env_var("PROTON_MODE", old_mode)
  defer restore_env_var("PROTON_DEV", old_dev)

  @env.unset_env_var("PROTON_DEV")
  @env.unset_env_var("PROTON_MODE")
  let resolved = unwrap_configuration(() => {
    config(config_path)
    .title("Code Title")
    .size(width=640, height=480)
    .titlebar_style(TitlebarStyle::Overlay)
    .entry_html("<main>code</main>")
    .debug(enabled=false)
    .resolved_app_config()
  })
  let manifest = resolved.manifest
  assert_eq(
    resolved.permission_base_path,
    facade_path_parent(resolve_entry_path(config_path).to_string()),
  )
  assert_eq(manifest.window.title, "Code Title")
  assert_eq(manifest.window.width, 640)
  assert_eq(manifest.window.height, 480)
  assert_eq(manifest.window.titlebar_style, @manifest.TitlebarStyle::Overlay)
  assert_eq(manifest.debug, 0)
  match manifest.entry {
    @manifest.AppEntry::Html(html) => assert_eq(html, "<main>code</main>")
    _ => fail("expected API entry override")
  }
}

///|
test "dev manifest uses env override or frontend dev_url" {
  let override_path = "target/proton-facade-dev/env-override.proton.project.json"
  write_facade_dev_config(override_path, dev_url="http://localhost:5173")
  let old_dev = @env.get_env_var("PROTON_DEV")
  let old_url = @env.get_env_var("PROTON_FRONTEND_URL")
  defer restore_env_var("PROTON_FRONTEND_URL", old_url)
  defer restore_env_var("PROTON_DEV", old_dev)

  @env.set_env_var("PROTON_DEV", "1")
  @env.set_env_var("PROTON_FRONTEND_URL", "http://localhost:3000")
  let override_manifest = unwrap_configuration(() => {
      config(override_path).resolved_app_config()
    }).manifest
  match override_manifest.entry {
    @manifest.AppEntry::Url(url) =>
      inspect(url, content="http://localhost:3000")
    _ => fail("expected dev URL entry")
  }

  let config_path = "target/proton-facade-dev/config-dev-url.proton.project.json"
  write_facade_dev_config(config_path, dev_url="http://localhost:5173")
  @env.unset_env_var("PROTON_FRONTEND_URL")
  let config_manifest = unwrap_configuration(() => {
      config(config_path).resolved_app_config()
    }).manifest
  match config_manifest.entry {
    @manifest.AppEntry::Url(url) =>
      inspect(url, content="http://localhost:5173")
    _ => fail("expected dev URL entry")
  }
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
test "single instance builder validates and resolves an inline identity" {
  let invalid = html("App", "<main>App</main>").single_instance(" ")
  assert_true(invalid.validation_error() is Some(_))
  let resolved = html("App", "<main>App</main>")
    .single_instance("dev.proton.inline")
    .inline_app_config()
  assert_eq(resolved.instance_identifier, Some("dev.proton.inline"))
}

///|
test "launch activation classifies URLs and existing documents" {
  let document = "target/proton-facade-activation.txt"
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.write_string_to_file(document, "activation", encoding="utf8") catch {
    error => abort(@debug.render(Repr(error)))
  }
  assert_true(launch_argument_is_url("dev.proton://open", ["dev.proton"]))
  assert_true(launch_argument_is_url("custom:value", ["custom"]))
  assert_false(launch_argument_is_url("custom:value", ["other"]))
  assert_true(launch_argument_is_document(document, ["txt"]))
  assert_false(launch_argument_is_document(document, ["md"]))
  assert_false(
    launch_argument_is_document("target/proton-facade-activation-missing.txt", [
      "txt",
    ]),
  )
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
test "app data directory follows platform conventions" {
  assert_eq(
    app_data_dir_for_platform(
      "macos",
      "com.example.devtoys",
      Some("/Users/test"),
      None,
      None,
    ),
    "/Users/test/Library/Application Support/com.example.devtoys",
  )
  assert_eq(
    app_data_dir_for_platform(
      "linux",
      "com.example.devtoys",
      Some("/home/test"),
      None,
      Some("/data"),
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
fn updater_test_channel(
  check_on_launch : Bool,
  identifier? : String? = Some("com.example.app"),
  version? : String? = Some("1.2.3"),
) -> ResolvedUpdateChannel? {
  let project = @bootstrap.ProtonProjectConfig::new(
    @bootstrap.LoadedAppManifest::new(
      @manifest.AppManifest::new(
        @manifest.WindowManifest::new("Test", 800, 600),
        @manifest.AppEntry::Url("https://example.com/"),
      ),
      base_dir=None,
    ),
    @bootstrap.ProtonAppMetadata::new("Test", identifier~, version~),
    updater=Some(
      @bootstrap.ProtonUpdaterConfig::new(
        "https://updates.example.com/latest.json",
        ["rsa-sha256:ab:010001"],
        check_on_launch~,
      ),
    ),
  )
  resolved_update_channel(project)
}

///|
/// Channel identity and release ordering come from the signed application
/// bundle rather than optional project release metadata.
test "an update channel does not require release metadata" {
  assert_true(updater_test_channel(true) is Some(_))
  assert_true(updater_test_channel(true, identifier=None) is Some(_))
  assert_true(updater_test_channel(true, version=None) is Some(_))
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
      { x: 1, y: 2, width: 300, height: 200, visible: true, z_order: 1 }
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
  assert_eq(view.as_native_ref(), @native.ViewRef::unsafe_from_handle(7L))
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
test "with_view stores declarative views and rejects invalid ids" {
  let app = html("Test", "<html></html>")
  inspect(app.planned_views.length(), content="0")
  let app = app.with_view(
    "browser",
    @native.ViewConfig::new(width=320, height=240, initial_url="about:blank"),
  )
  inspect(app.planned_views.length(), content="1")
  let app = app.with_view("browser", @native.ViewConfig::new(width=1, height=1))
  let app = app.with_view("  ", @native.ViewConfig::new(width=1, height=1))
  inspect(app.planned_views.length(), content="1")
  inspect(app.validation_errors.length(), content="2")
}
