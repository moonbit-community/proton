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
fn test_command_spec(
  extension_id : String,
  js_namespace : String,
  api_names : Array[String],
) -> @proton_command.AppCommandExtensionSpec {
  @proton_command.AppCommandExtensionSpec::new(
    extension_id,
    js_namespace,
    api_names.map(fn(api_name) {
      @proton_command.AppCommandApiDescriptor::new(api_name)
    }),
    fn(_context) { Ok(()) },
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
  let script = extension_event_dispatch_script(event, None)
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
test "extension event dispatch script can target a page instance" {
  let event = @ipc.IpcExtensionEvent::new("ticker", "done", Json::null())
  let script = extension_event_dispatch_script(event, Some("page-1"))
  assert_true(script.contains("root.core['@@pageInstance']"))
  assert_true(script.contains("\"page-1\""))
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
