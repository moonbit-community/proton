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
) -> @proton_command.AppCommandExtensionSpec {
  @proton_command.AppCommandExtensionSpec::new(
    extension_id,
    js_namespace,
    api_names.map(fn(api_name) {
      @proton_command.AppCommandApiDescriptor::new(api_name)
    }),
    fn(_context) {  },
    dependencies~,
  )
}

///|
fn test_tracking_command_spec(
  extension_id : String,
  js_namespace : String,
  registered : Array[String],
  dependencies? : Array[String] = [],
) -> @proton_command.AppCommandExtensionSpec {
  @proton_command.AppCommandExtensionSpec::new(
    extension_id,
    js_namespace,
    [],
    fn(_context) { registered.push(extension_id) },
    dependencies~,
  )
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
  let manifest = test_command_manifest(extension_id)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  command_extensions[extension_id] = test_command_spec(extension_id, "add", [
    "slowAdd",
  ])
  let config = unwrap_configuration(() => {
    build_bridge_frontend_config(manifest, command_extensions)
  })
  inspect(config.extensions.length(), content="1")
  inspect(config.extensions[0].js_namespace, content="add")
  assert_eq(config.extensions[0].apis, ["slowAdd"])
  assert_eq(config.initialization_units, [])
}

///|
test "bridge frontend config preserves initialization unit ownership" {
  let extension_id = "examples/scripts"
  let manifest = test_command_manifest(extension_id)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  command_extensions[extension_id] = @proton_command.AppCommandExtensionSpec::new(
    extension_id,
    "scripts",
    [],
    fn(_context) {  },
    scripts=["globalThis.first = true;", "globalThis.second = true;"],
  )
  let config = unwrap_configuration(() => {
    build_bridge_frontend_config(manifest, command_extensions)
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
async test "app run requires the Proton application runner" {
  let mut rejected = false
  html("Test", "<html></html>").run() catch {
    RunnerError(message) => {
      rejected = true
      assert_true(message.contains("@proton.run"))
      assert_true(message.contains("synchronous main"))
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
  run_manifest(manifest, command_extensions, None, None, 30000, true) catch {
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
  run_manifest(manifest, command_extensions, None, Some(menu), 30000, true) catch {
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
test "extension events use structured bridge transport JSON" {
  let event = @ipc.IpcExtensionEvent::new(
    "ticker",
    "tick",
    Json::object({
      "text": Json::string("</script><p>escaped</p>"),
      "index": Json::number(1),
    }),
  )
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
test "asset urls resolve under the local file path" {
  let path = "46_asset_sidecar_resources/app/app.html"
  let base = asset_base_url(path).replace_all(old="\\", new="/")
  let document = asset_document_url(path).replace_all(old="\\", new="/")
  assert_true(base.has_prefix("proton://app/"))
  assert_true(base.has_suffix("/46_asset_sidecar_resources/app/"))
  assert_true(document.has_prefix("proton://app/"))
  assert_true(document.has_suffix("/46_asset_sidecar_resources/app/app.html"))
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
  let event = @ipc.IpcExtensionEvent::new("ticker", "done", Json::null())
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
    Json::object({
      "command_id": Json::string("demo.refresh"),
      "window": Json::string("17"),
    }),
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
      InvalidDevelopmentUrl(reason~, ..) =>
        assert_true(reason.contains(expected_reason))
      error => fail(error.message())
    }
  }
}

///|
test "bridge frontend config ignores disabled command extensions" {
  let extension_id = "examples/async-add"
  let manifest = test_command_manifest(extension_id, enabled=false)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  command_extensions[extension_id] = test_command_spec(extension_id, "add", [
    "slowAdd",
  ])
  let config = unwrap_configuration(() => {
    build_bridge_frontend_config(manifest, command_extensions)
  })
  assert_eq(config.extensions, [])
  assert_eq(config.initialization_units, [])
}

///|
test "bridge frontend config can omit command extensions" {
  let extension_id = "examples/async-add"
  let manifest = test_command_manifest(extension_id, enabled=false)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  command_extensions[extension_id] = test_command_spec(extension_id, "add", [
    "slowAdd",
  ])
  let config = unwrap_configuration(() => {
    build_bridge_frontend_config(manifest, command_extensions)
  })
  inspect(config.extensions.length(), content="0")
  assert_eq(config.initialization_units, [])
}

///|
test "command host close runs extension destroy hooks once" {
  let extension_id = "examples/destroy"
  let destroyed = Ref(0)
  let manifest = test_command_manifest(extension_id)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  command_extensions[extension_id] = @proton_command.AppCommandExtensionSpec::new(
    extension_id,
    "destroyTest",
    [@proton_command.AppCommandApiDescriptor::new("ping")],
    fn(context) raise { context.op("ping", fn(_payload : Unit) { "pong" }) },
    on_destroy=fn(context) {
      if context.extension_id() == extension_id {
        destroyed.val = destroyed.val + 1
      }
    },
  )
  match
    unwrap_app_run(() => build_command_host(manifest, command_extensions, None)) {
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
        None,
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
  command_extensions[base_id] = @proton_command.AppCommandExtensionSpec::new(
    base_id,
    "baseDestroy",
    [],
    fn(_context) {  },
    on_destroy=fn(_context) { destroyed.push(base_id) },
  )
  command_extensions[feature_id] = @proton_command.AppCommandExtensionSpec::new(
    feature_id,
    "featureDestroy",
    [],
    fn(_context) {  },
    dependencies=[base_id],
    on_destroy=fn(_context) raise {
      destroyed.push(feature_id)
      raise FacadeLifecycleTestError::DestroyFailed(feature_id)
    },
  )
  match
    unwrap_app_run(() => build_command_host(manifest, command_extensions, None)) {
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
  command_extensions[extension_id] = @proton_command.AppCommandExtensionSpec::new(
    extension_id,
    "registrationCleanup",
    [],
    fn(_context) raise {
      raise FacadeLifecycleTestError::DestroyFailed("registration")
    },
    on_destroy=fn(_context) raise {
      raise FacadeLifecycleTestError::DestroyFailed("cleanup")
    },
  )
  let error = expect_app_run_error(() => {
    ignore(build_command_host(manifest, command_extensions, None))
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
  assert_true(lifecycle.window_state is NotCreated)
  lifecycle.begin_starting()
  lifecycle.begin_window_create()
  lifecycle.finish_window_create()
  lifecycle.begin_running()
  assert_true(lifecycle.state is Running)
  assert_true(lifecycle.window_state is Live)
  lifecycle.observe_window_closed()
  assert_true(lifecycle.state is Closing)
  assert_true(lifecycle.window_state is VisiblyClosed)
  lifecycle.begin_draining()
  lifecycle.begin_destroying()
  lifecycle.finish_window_destroy()
  lifecycle.finish()
  assert_true(lifecycle.state is Closed)
  assert_true(lifecycle.window_state is Destroyed)
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
      ApplicationContext::new(group),
      group,
      [],
    )
    group.return_immediately(())
  })
  assert_eq(calls, ["start:first", "start:second", "stop:second", "stop:first"])
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
        ApplicationContext::new(group),
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
        @native.WindowRef::unsafe_from_handle(17L),
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
test "core spec command wrapper destroys runtime core host" {
  let extension_id = "examples/core-destroy"
  let destroyed = Ref(0)
  let core_spec = @core.ExtensionSpec::new(extension_id, "coreDestroy", fn(
    _context,
  ) {
    @core.Extension::new(
      extension_id,
      "coreDestroy",
      fn(extension) raise {
        extension.op("ping", fn(_payload : Unit) { "pong" })
      },
      on_destroy=fn(_extension) { destroyed.val = destroyed.val + 1 },
    )
  })
  let command_spec_option = @proton_extension.from_core_spec(core_spec).command_spec() catch {
    error => abort(error.message())
  }
  let command_spec = match command_spec_option {
    Some(spec) => spec
    None => fail("expected command spec")
  }
  assert_eq(destroyed.val, 1)
  let manifest = test_command_manifest(extension_id)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  command_extensions[extension_id] = command_spec
  match
    unwrap_app_run(() => build_command_host(manifest, command_extensions, None)) {
    Some(host) => {
      ignore(close_command_host(Some(host)))
      assert_eq(destroyed.val, 2)
    }
    _ => fail("expected command host")
  }
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
  match
    unwrap_app_run(() => build_command_host(manifest, command_extensions, None)) {
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
    expect_app_run_error(() => {
      build_command_host(manifest, command_extensions, None)
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
test "bridge frontend config rejects invalid namespace and API names" {
  let namespace_extension_id = "examples/bad-namespace"
  let namespace_manifest = test_command_manifest(namespace_extension_id)
  let namespace_extensions : Map[
    String,
    @proton_command.AppCommandExtensionSpec,
  ] = Map([])
  namespace_extensions[namespace_extension_id] = test_command_spec(
    namespace_extension_id,
    "core",
    ["slowAdd"],
  )
  match
    expect_configuration_error(() => {
      build_bridge_frontend_config(namespace_manifest, namespace_extensions)
    }) {
    InvalidJavaScriptNamespace(js_namespace~) => assert_eq(js_namespace, "core")
    error => fail(error.message())
  }

  let api_extension_id = "examples/bad-api"
  let api_manifest = test_command_manifest(api_extension_id)
  let api_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  api_extensions[api_extension_id] = test_command_spec(
    api_extension_id,
    "add",
    ["__proto__"],
  )
  match
    expect_configuration_error(() => {
      build_bridge_frontend_config(api_manifest, api_extensions)
    }) {
    InvalidJavaScriptApi(js_namespace~, api_name~) => {
      assert_eq(js_namespace, "add")
      assert_eq(api_name, "__proto__")
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
  let frontend = match dev_url {
    Some(url) => "\nfrontend = {\n  dev_url: \"" + url + "\",\n}\n"
    None => ""
  }
  let base =
    #|window = {
    #|  title: "Dev Test",
    #|  width: 320,
    #|  height: 240,
    #|}
    #|
    #|entry = {
    #|  kind: "asset",
    #|  value: "app.html",
    #|}
    #|
    #|debug = true
    #|
  @mbfs.write_string_to_file(path, base + frontend, encoding="utf8") catch {
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
  let config_path = "target/proton-facade-dev/implicit-env.moon.proton"
  write_facade_dev_config(config_path)
  let old_config = @env.get_env_var("PROTON_CONFIG_PATH")
  defer restore_env_var("PROTON_CONFIG_PATH", old_config)

  @env.set_env_var("PROTON_CONFIG_PATH", config_path)
  @debug.assert_eq(implicit_config_path(), Some(config_path))
}

///|
test "default config API honors PROTON_CONFIG_PATH" {
  let config_path = "target/proton-facade-dev/config-api-env.moon.proton"
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
  let app = config("moon.proton")
  @debug.assert_eq(app.file_path, Some(config_path))
  let resolved = unwrap_configuration(() => app.resolved_app_config())
  assert_eq(resolved.manifest.window.title, "Dev Test")
}

///|
test "config API keeps non-default paths explicit" {
  let config_path = "target/proton-facade-dev/explicit.moon.proton"
  let env_path = "target/proton-facade-dev/explicit-env.moon.proton"
  write_facade_dev_config(config_path)
  write_facade_dev_config(env_path)
  let old_config = @env.get_env_var("PROTON_CONFIG_PATH")
  defer restore_env_var("PROTON_CONFIG_PATH", old_config)

  @env.set_env_var("PROTON_CONFIG_PATH", env_path)
  @debug.assert_eq(config(config_path).file_path, Some(config_path))
}

///|
test "config API overrides manifest fields and keeps base dir" {
  let config_path = "target/proton-facade-dev/api-overrides.moon.proton"
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
  assert_eq(manifest.window.title, "Code Title")
  assert_eq(manifest.window.width, 640)
  assert_eq(manifest.window.height, 480)
  assert_eq(manifest.window.titlebar_style, @manifest.TitlebarStyle::Overlay)
  assert_eq(manifest.debug, 0)
  match manifest.entry {
    @manifest.AppEntry::Html(html) => assert_eq(html, "<main>code</main>")
    _ => fail("expected API entry override")
  }
  match resolved.base_dir {
    Some(base_dir) =>
      assert_true(
        base_dir
        .replace_all(old="\\", new="/")
        .has_suffix("target/proton-facade-dev"),
      )
    None => fail("expected config base dir")
  }
}

///|
test "dev manifest uses env override or frontend dev_url" {
  let override_path = "target/proton-facade-dev/env-override.moon.proton"
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

  let config_path = "target/proton-facade-dev/config-dev-url.moon.proton"
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
