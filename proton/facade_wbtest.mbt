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
priv suberror NotificationClickHandlerFailure

///|
priv suberror RuntimeBodyFailure

///|
test "app cache directory reaches the facade runtime configuration" {
  let app = url("Test", "https://example.invalid").cache_dir("profile")
  assert_eq(app.cache_dir, Some("profile"))
}

///|
test "app exposes its before-runtime-cleanup callback" {
  let called = Ref(false)
  let app = url("Test", "https://example.invalid").on_before_runtime_cleanup(() => {
    called.val = true
  })
  match app.before_runtime_cleanup_handler {
    Some(handler) => handler()
    None => fail("before-runtime-cleanup callback was not configured")
  }
  assert_true(called.val)
}

///|
test "runtime cleanup boundary signals once before cleanup" {
  let events : Array[String] = []
  let boundary = RuntimeCleanupBoundary::{
    before_cleanup: Some(() => events.push("before")),
    started: false,
  }
  let first = boundary.run(() => {
    events.push("host")
    events.push("window")
    events.push("runtime")
    Ok(())
  })
  let second = boundary.run(() => {
    events.push("unexpected second cleanup")
    Ok(())
  })
  assert_true(first is Ok(_))
  assert_true(second is Ok(_))
  @debug.assert_eq(events, ["before", "host", "window", "runtime"])
}

///|
test "runtime cleanup still runs when its early callback fails" {
  let cleanup_called = Ref(false)
  let boundary = RuntimeCleanupBoundary::{
    before_cleanup: Some(fn() raise { raise RuntimeBodyFailure }),
    started: false,
  }
  let result = boundary.run(() => {
    cleanup_called.val = true
    Ok(())
  })
  assert_true(result is Ok(_))
  assert_true(cleanup_called.val)
}

///|
async test "native runtime cleanup runs once when the pump raises" {
  let cleanups = Ref(0)
  try
    run_with_cleanup(
      async fn() {
        @async.sleep(0)
        raise RuntimeBodyFailure
      },
      () => {
        cleanups.val = cleanups.val + 1
        Ok(())
      },
    )
  catch {
    RuntimeBodyFailure => ()
    error => raise error
  } noraise {
    _ => fail("raising pump completed normally")
  }
  assert_eq(cleanups.val, 1)
}

///|
async test "native runtime cleanup runs once when the pump is cancelled" {
  let cleanups = Ref(0)
  @async.with_task_group(group => {
    let task = group.spawn(
      () => {
        run_with_cleanup(
          async fn() {
            @async.sleep(1_000)
            Ok(())
          },
          () => {
            cleanups.val = cleanups.val + 1
            Ok(())
          },
        )
      },
      allow_failure=true,
    )
    @async.sleep(1)
    task.cancel()
    try task.wait() catch {
      error => assert_true(@async.is_cancellation_error(error))
    } noraise {
      _ => fail("cancelled pump completed normally")
    }
    assert_eq(cleanups.val, 1)
  })
}

///|
async test "notification click handler takes precedence over legacy fallback" {
  let handled : Array[String] = []
  let forwarded : Array[String] = []
  let app = html("Test", "<html></html>").on_notification_click(payload => {
    handled.push(payload)
  })
  dispatch_notification_click(
    "notification-payload",
    app.notification_click_handler,
    Some(payload => forwarded.push(payload)),
  )
  @debug.assert_eq(handled, ["notification-payload"])
  assert_true(forwarded.is_empty())
}

///|
async test "notification click handler failures are best effort" {
  let fallback_called = Ref(false)
  dispatch_notification_click(
    "notification-payload",
    Some(_ => raise NotificationClickHandlerFailure),
    Some(_ => fallback_called.val = true),
  )
  assert_false(fallback_called.val)
}

///|
async test "notification click dispatch preserves legacy and inert defaults" {
  let forwarded : Array[String] = []
  dispatch_notification_click(
    "legacy-payload",
    None,
    Some(payload => forwarded.push(payload)),
  )
  dispatch_notification_click("window-payload", None, None)
  @debug.assert_eq(forwarded, ["legacy-payload"])
}

///|
async test "notification click handler propagates task cancellation" {
  let entered = Ref(false)
  @async.with_task_group(group => {
    let task = group.spawn(
      () => {
        dispatch_notification_click(
          "notification-payload",
          Some(async fn(_) {
            entered.val = true
            @async.sleep(1_000)
          }),
          None,
        )
      },
      allow_failure=true,
    )
    @async.sleep(1)
    assert_true(entered.val)
    task.cancel()
    try task.wait() catch {
      error => assert_true(@async.is_cancellation_error(error))
    } noraise {
      _ => fail("cancelled notification handler completed normally")
    }
  })
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
test "command proxy can install event bus without command extensions" {
  let extension_id = "examples/async-add"
  let manifest = test_command_manifest(extension_id, enabled=false)
  let command_extensions : Map[String, @proton_command.AppCommandExtensionSpec] = {}
  command_extensions[extension_id] = test_command_spec(extension_id, "add", [
    "slowAdd",
  ])
  match
    build_command_proxy_script(
      manifest,
      command_extensions,
      install_event_bus=true,
    ) {
    Ok(Some(script)) => {
      assert_true(script.contains("root.events = events;"))
      assert_true(script.contains("events.on = function(name, listener)"))
      assert_true(script.contains("events['@@emitFrontendEvent']"))
      assert_true(script.contains("var specs = [];"))
    }
    _ => fail("expected event bus bootstrap script")
  }
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
