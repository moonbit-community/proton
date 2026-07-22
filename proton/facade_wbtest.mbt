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
    fn(_context) { Ok(()) },
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
    fn(_context) {
      registered.push(extension_id)
      Ok(())
    },
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
  match build_bridge_frontend_config(manifest, command_extensions) {
    Ok(config) => {
      inspect(config.extensions.length(), content="1")
      inspect(config.extensions[0].js_namespace, content="add")
      assert_eq(config.extensions[0].apis, ["slowAdd"])
      assert_eq(config.initialization_units, [])
    }
    Err(error) => fail(error)
  }
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
    fn(_context) { Ok(()) },
    scripts=["globalThis.first = true;", "globalThis.second = true;"],
  )
  match build_bridge_frontend_config(manifest, command_extensions) {
    Err(error) => fail(error)
    Ok(config) => {
      inspect(config.initialization_units.length(), content="2")
      inspect(config.initialization_units[0].owner, content="examples/scripts")
      inspect(config.initialization_units[0].name, content="script-0")
      inspect(
        config.initialization_units[1].source,
        content="globalThis.second = true;",
      )
    }
  }
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
  assert_true(app_run_error_text(error).contains("bridge_bootstrap_failed"))
}

///|
test "bridge startup timeout is finite and configurable" {
  let default_app = html("Test", "<html></html>")
  inspect(default_app.bridge_startup_timeout_value_ms, content="30000")
  let configured = default_app.bridge_startup_timeout_ms(2500)
  inspect(configured.bridge_startup_timeout_value_ms, content="2500")
  assert_eq(configured.validation_error(), None)
  assert_eq(
    configured.bridge_startup_timeout_ms(0).validation_error(),
    Some("bridge startup timeout must be positive"),
  )
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
  match url_origin("http://localhost:5173/app") {
    Ok(origin) => assert_eq(origin, "http://localhost:5173")
    Err(error) => fail(error)
  }
  match url_origin("https://localhost/app") {
    Ok(origin) => assert_eq(origin, "https://localhost")
    Err(error) => fail(error)
  }
  match url_origin("http://127.0.0.1:3000") {
    Ok(origin) => assert_eq(origin, "http://127.0.0.1:3000")
    Err(error) => fail(error)
  }
  match url_origin("http://[::1]:5173/app") {
    Ok(origin) => assert_eq(origin, "http://[::1]:5173")
    Err(error) => fail(error)
  }
  match url_origin("HTTP://LOCALHOST:80/app") {
    Ok(origin) => assert_eq(origin, "http://localhost")
    Err(error) => fail(error)
  }
  match url_origin("https://Example.COM:443/app") {
    Ok(origin) => assert_eq(origin, "https://example.com")
    Err(error) => fail(error)
  }
  match url_origin("http://LOCALHOST:05173/app") {
    Ok(origin) => assert_eq(origin, "http://localhost:5173")
    Err(error) => fail(error)
  }
  match url_origin("ftp://localhost:5173/app") {
    Err(error) => assert_true(error.contains("http or https"))
    Ok(_) => fail("expected non-http dev origin to fail")
  }
  match url_origin("http://local\"host:5173/app") {
    Err(error) => assert_true(error.contains("invalid origin"))
    Ok(_) => fail("expected quoted dev origin to fail")
  }
  match url_origin("http://local\\host:5173/app") {
    Err(error) => assert_true(error.contains("invalid origin"))
    Ok(_) => fail("expected backslash dev origin to fail")
  }
  match url_origin("http://localhost:/app") {
    Err(error) => assert_true(error.contains("port must not be empty"))
    Ok(_) => fail("expected empty dev origin port to fail")
  }
  match url_origin("http://[::1]5173/app") {
    Err(error) => assert_true(error.contains("invalid IPv6 origin"))
    Ok(_) => fail("expected invalid IPv6 dev origin to fail")
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
  match build_bridge_frontend_config(manifest, command_extensions) {
    Ok(config) => {
      assert_eq(config.extensions, [])
      assert_eq(config.initialization_units, [])
    }
    Err(error) => fail(error)
  }
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
  match build_bridge_frontend_config(manifest, command_extensions) {
    Ok(config) => {
      inspect(config.extensions.length(), content="0")
      assert_eq(config.initialization_units, [])
    }
    Err(error) => fail(error)
  }
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
    fn(context) {
      context.op("ping", fn(_payload : Unit) { "pong" })
      Ok(())
    },
    on_destroy=fn(context) {
      if context.extension_id() == extension_id {
        destroyed.val = destroyed.val + 1
      }
    },
  )
  match build_command_host(manifest, command_extensions, None) {
    Ok(Some(host)) => {
      close_command_host(Some(host))
      assert_eq(destroyed.val, 1)
      close_command_host(Some(host))
      assert_eq(destroyed.val, 1)
    }
    _ => fail("expected command host")
  }
}

///|
test "core spec command wrapper destroys runtime core host" {
  let extension_id = "examples/core-destroy"
  let destroyed = Ref(0)
  let core_spec = @core.ExtensionSpec::new(extension_id, "coreDestroy", fn(
    _context,
  ) {
    Ok(
      @core.Extension::new(
        extension_id,
        "coreDestroy",
        fn(extension) { extension.op("ping", fn(_payload : Unit) { "pong" }) },
        on_destroy=fn(_extension) { destroyed.val = destroyed.val + 1 },
      ),
    )
  })
  let command_spec = match
    @proton_extension.from_core_spec(core_spec).command_spec() {
    Some(spec) => spec
    None => fail("expected command spec")
  }
  assert_eq(destroyed.val, 1)
  let manifest = test_command_manifest(extension_id)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = Map([],
  )
  command_extensions[extension_id] = command_spec
  match build_command_host(manifest, command_extensions, None) {
    Ok(Some(host)) => {
      close_command_host(Some(host))
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
  match build_command_host(manifest, command_extensions, None) {
    Ok(Some(host)) => {
      close_command_host(Some(host))
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
  match build_command_host(manifest, command_extensions, None) {
    Err(error) =>
      assert_eq(
        error, "command extension examples/feature requires missing dependency examples/base",
      )
    Ok(_) => fail("expected missing dependency error")
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
  match build_bridge_frontend_config(namespace_manifest, namespace_extensions) {
    Err(error) =>
      assert_true(
        error.contains(
          "command extension namespace cannot be exposed to JavaScript: core",
        ),
      )
    Ok(_) => fail("expected invalid namespace to fail")
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
  match build_bridge_frontend_config(api_manifest, api_extensions) {
    Err(error) =>
      assert_true(
        error.contains(
          "command extension API cannot be exposed to JavaScript: add.__proto__",
        ),
      )
    Ok(_) => fail("expected invalid API name to fail")
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
    err => abort(@debug.render(@debug.to_repr(err)))
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
  let resolved = match app.resolved_app_config() {
    Ok(resolved) => resolved
    Err(error) => abort(error)
  }
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
  let resolved = match
    config(config_path)
    .title("Code Title")
    .size(width=640, height=480)
    .titlebar_style(TitlebarStyle::Overlay)
    .entry_html("<main>code</main>")
    .debug(enabled=false)
    .resolved_app_config() {
    Ok(resolved) => resolved
    Err(error) => abort(error)
  }
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
  let override_manifest = match config(override_path).resolved_app_config() {
    Ok(resolved) => resolved.manifest
    Err(error) => abort(error)
  }
  match override_manifest.entry {
    @manifest.AppEntry::Url(url) =>
      inspect(url, content="http://localhost:3000")
    _ => fail("expected dev URL entry")
  }

  let config_path = "target/proton-facade-dev/config-dev-url.moon.proton"
  write_facade_dev_config(config_path, dev_url="http://localhost:5173")
  @env.unset_env_var("PROTON_FRONTEND_URL")
  let config_manifest = match config(config_path).resolved_app_config() {
    Ok(resolved) => resolved.manifest
    Err(error) => abort(error)
  }
  match config_manifest.entry {
    @manifest.AppEntry::Url(url) =>
      inspect(url, content="http://localhost:5173")
    _ => fail("expected dev URL entry")
  }
}
