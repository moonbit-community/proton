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
  let extensions : Map[String, @manifest.ExtensionSetting] = {}
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
  let extensions : Map[String, @manifest.ExtensionSetting] = {}
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
test "command proxy script reflects enabled command extension metadata" {
  let extension_id = "examples/async-add"
  let manifest = test_command_manifest(extension_id)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = {}
  command_extensions[extension_id] = test_command_spec(extension_id, "add", [
    "slowAdd",
  ])
  match build_command_proxy_script(manifest, command_extensions) {
    Ok(Some(script)) => {
      assert_true(script.contains("\"namespace\":\"add\""))
      assert_true(script.contains("\"apis\":[\"slowAdd\"]"))
      assert_true(
        script.contains(
          "core.invokeOp('ext:' + namespace + '/' + apiName, payload)",
        ),
      )
      assert_true(script.contains("window.__MoonBit__ = root;"))
      assert_true(script.contains("root.events = events;"))
      assert_true(script.contains("root['@@exactListeners'] = exactListeners"))
      assert_true(script.contains("events['@@emitExtensionEvent']"))
      assert_true(script.contains("events.on = function(name, listener)"))
      assert_true(script.contains("target.on = (function(ns)"))
    }
    _ => fail("expected command proxy script")
  }
}

///|
test "extension event dispatch script calls page event emitter with JSON data" {
  let event = @ipc.IpcExtensionEvent::new(
    "ticker",
    "tick",
    Json::object({
      "text": Json::string("</script><p>escaped</p>"),
      "index": Json::number(1),
    }),
  )
  let script = extension_event_dispatch_script(
    event,
    None,
    default_bridge_page_policy(),
  )
  assert_true(script.contains("window.location.protocol !== 'proton:'"))
  assert_true(script.contains("events['@@emitExtensionEvent']"))
  assert_true(script.contains("event.extension_namespace"))
  assert_true(script.contains("\"extension_namespace\":\"ticker\""))
  assert_true(script.contains("\"event_name\":\"tick\""))
  assert_true(script.contains("\"text\":\"</script><p>escaped</p>\""))
  let injected = inject_command_proxy_script("<main></main>", Some(script))
  inspect(injected.contains("</script><p>escaped</p>"), content="false")
  inspect(injected.contains("<\\/script><p>escaped</p>"), content="true")
}

///|
test "file entry bootstrap keeps relative assets under original directory" {
  let html =
    #|<html><head><link rel="stylesheet" href="app.css"></head><body><script src="app.js"></script></body></html>
  let injected = inject_html_bootstrap(
    html,
    base_tag("proton://app/D:/Code/proton-demo/app/") +
    script_tag("window.__MoonBit__ = {};</script><p>tail</p>"),
  )
  assert_true(
    injected.contains(
      "<head>\n<base href=\"proton://app/D:/Code/proton-demo/app/\">\n<script>",
    ),
  )
  assert_true(injected.contains("href=\"app.css\""))
  assert_true(injected.contains("src=\"app.js\""))
  inspect(injected.contains("</script><p>tail</p>"), content="false")
  inspect(injected.contains("<\\/script><p>tail</p>"), content="true")
}

///|
test "file url resolves local paths" {
  let url = file_url("app/app.html").replace_all(old="\\", new="/")
  assert_true(url.has_prefix("file:///"))
  assert_true(url.has_suffix("/app/app.html"))
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
test "extension event dispatch script can target a page instance" {
  let event = @ipc.IpcExtensionEvent::new("ticker", "done", Json::null())
  let script = extension_event_dispatch_script(event, Some("page-1"), BridgePagePolicy::{
    dev_origin: Some("http://localhost:5173"),
    request_timeout_ms: 30000,
  })
  assert_true(
    script.contains("window.location.origin !== \"http://localhost:5173\""),
  )
  assert_true(script.contains("root.core['@@pageInstance']"))
  assert_true(script.contains("\"page-1\""))
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
test "command proxy script ignores disabled command extensions" {
  let extension_id = "examples/async-add"
  let manifest = test_command_manifest(extension_id, enabled=false)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = {}
  command_extensions[extension_id] = test_command_spec(extension_id, "add", [
    "slowAdd",
  ])
  debug_inspect(
    build_command_proxy_script(manifest, command_extensions),
    content="Ok(None)",
  )
}

///|
test "command host close runs extension destroy hooks once" {
  let extension_id = "examples/destroy"
  let destroyed = Ref(0)
  let manifest = test_command_manifest(extension_id)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = {}
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
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = {}
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
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = {}
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
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = {}
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
test "command proxy script rejects invalid namespace and API names" {
  let namespace_extension_id = "examples/bad-namespace"
  let namespace_manifest = test_command_manifest(namespace_extension_id)
  let namespace_extensions : Map[
    String,
    @proton_command.AppCommandExtensionSpec,
  ] = {}
  namespace_extensions[namespace_extension_id] = test_command_spec(
    namespace_extension_id,
    "core",
    ["slowAdd"],
  )
  match build_command_proxy_script(namespace_manifest, namespace_extensions) {
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
  let api_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = {}
  api_extensions[api_extension_id] = test_command_spec(
    api_extension_id,
    "add",
    ["__proto__"],
  )
  match build_command_proxy_script(api_manifest, api_extensions) {
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
test "command proxy injection uses first head body or prepend fallback" {
  let script = "window.__MoonBit__ = {};</script><p>tail</p>"
  let head_html = "<html><head><title>A</title></head><head></head></html>"
  let injected_head = inject_command_proxy_script(head_html, Some(script))
  assert_true(injected_head.contains("<head>\n<script>"))
  inspect(injected_head.contains("</script><p>tail</p>"), content="false")
  inspect(injected_head.contains("<\\/script><p>tail</p>"), content="true")
  inspect(injected_head.contains("</head><head>\n<script>"), content="false")

  let body_html = "<html><body><main></main></body></html>"
  let injected_body = inject_command_proxy_script(body_html, Some("x"))
  assert_true(injected_body.has_prefix("<html><script>x</script>\n<body>"))

  let bare_html = "<main></main>"
  let injected_bare = inject_command_proxy_script(bare_html, Some("x"))
  assert_true(injected_bare.has_prefix("<script>x</script>\n<main>"))
  inspect(inject_command_proxy_script(bare_html, None), content="<main></main>")
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
