///|
fn assert_runtime_entry(
  actual : @wvrt.AppEntry,
  expected : @wvrt.AppEntry,
) -> Unit raise {
  match (actual, expected) {
    (Html(actual), Html(expected)) => assert_eq(actual, expected)
    (Url(actual), Url(expected)) => assert_eq(actual, expected)
    (File(actual), File(expected)) => assert_eq(actual, expected)
    (Asset(actual), Asset(expected)) => assert_eq(actual, expected)
    _ => abort("runtime entry mismatch")
  }
}

///|
fn assert_runtime_config(
  actual : @wvrt.AppConfig,
  expected : @wvrt.AppConfig,
) -> Unit raise {
  assert_eq(actual.window.title, expected.window.title)
  assert_eq(actual.window.width, expected.window.width)
  assert_eq(actual.window.height, expected.window.height)
  assert_eq(actual.debug, expected.debug)
  assert_runtime_entry(actual.entry, expected.entry)
  assert_eq(actual.windows.length(), expected.windows.length())
  for index, actual_window in actual.windows {
    let expected_window = expected.windows[index]
    assert_eq(actual_window.id, expected_window.id)
    assert_eq(actual_window.window.title, expected_window.window.title)
    assert_eq(actual_window.window.width, expected_window.window.width)
    assert_eq(actual_window.window.height, expected_window.window.height)
    assert_runtime_entry(actual_window.entry, expected_window.entry)
  }
}

///|
test "app builder creates same runtime config as manual manifest" {
  let builder_manifest = AppBuilder::html(
      "Builder",
      900,
      700,
      "<html></html>",
      debug=1,
      size_hint=@manifest.WindowSizeHint::Min,
    )
    .window_file(
      "settings",
      "Settings",
      420,
      320,
      "settings.html",
      size_hint=@manifest.WindowSizeHint::Fixed,
    )
    .manifest()
  let manual_manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new(
      "Builder",
      900,
      700,
      size_hint=@manifest.WindowSizeHint::Min,
    ),
    @manifest.AppEntry::Html("<html></html>"),
    debug=1,
    windows=[
      @manifest.AppWindowManifest::new(
        "settings",
        @manifest.WindowManifest::new(
          "Settings",
          420,
          320,
          size_hint=@manifest.WindowSizeHint::Fixed,
        ),
        @manifest.AppEntry::File("settings.html"),
      ),
    ],
  )
  assert_runtime_config(
    runtime_config_from_manifest(builder_manifest),
    runtime_config_from_manifest(manual_manifest),
  )
}

///|
test "app builder extension links and enables extension" {
  let builder = AppBuilder::html("Builder", 900, 700, "<html></html>").extension(
    stub_extension("vendor/demo", js_namespace=Some("demo")),
  )
  @debug.assert_eq(
    builder.manifest().extension_setting("vendor/demo"),
    Some(@manifest.ExtensionSetting::enabled()),
  )
  match builder.registry() {
    Err(error) => abort(error)
    Ok(registry) => @debug.assert_eq(registry.registered_ids(), ["vendor/demo"])
  }
}

///|
test "app builder extension options are preserved" {
  let options = Json::object({ "scope": Json::string("read") })
  let builder = AppBuilder::html("Builder", 900, 700, "<html></html>").extension_with_options(
    stub_extension("vendor/demo", js_namespace=Some("demo")),
    options,
  )
  match options {
    Object(object) => object["late"] = Json::boolean(true)
    _ => abort("expected object options")
  }
  match builder.manifest().extension_setting("vendor/demo") {
    Some(setting) =>
      match setting.options() {
        Some(Object(object)) => {
          @debug.assert_eq(object.get("scope"), Some(Json::string("read")))
          @debug.assert_eq(object.get("late"), None)
        }
        _ => abort("expected extension options")
      }
    None => abort("expected enabled extension setting")
  }
}

///|
test "app builder duplicate extension ids return error" {
  let builder = AppBuilder::html("Builder", 900, 700, "<html></html>")
    .extension(stub_extension("vendor/demo", js_namespace=Some("demo")))
    .extension(stub_extension("vendor/demo", js_namespace=Some("demoAgain")))
  match builder.build() {
    Err(error) => assert_eq(error, "duplicate extension id: vendor/demo")
    Ok(app) => {
      app.destroy()
      abort("expected duplicate extension id error")
    }
  }
}

///|
test "app builder duplicate secondary window ids return error" {
  let builder = AppBuilder::html("Builder", 900, 700, "<html></html>")
    .window_html("settings", "Settings", 420, 320, "<html></html>")
    .window_url("settings", "Settings Again", 420, 320, "https://example.com")
  match builder.build() {
    Err(error) => assert_eq(error, "duplicate window id: settings")
    Ok(app) => {
      app.destroy()
      abort("expected duplicate window id error")
    }
  }
}

///|
test "app file builder links specs without enabling extensions" {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  let path = "target/app-file-builder-wbtest.json"
  let fixture =
    #|{
    #|  "window": {
    #|    "title": "File Builder",
    #|    "width": 900,
    #|    "height": 700
    #|  },
    #|  "entry": {
    #|    "kind": "html",
    #|    "value": "<html></html>"
    #|  }
    #|}
  @mbfs.write_string_to_file(path, fixture) catch {
    _ => abort("failed to write app file builder fixture")
  }
  let builder = AppFileBuilder::new(path).link(
    stub_extension("vendor/demo", js_namespace=Some("demo")),
  )
  let registry = match builder.registry() {
    Err(error) => abort(error)
    Ok(registry) => registry
  }
  @debug.assert_eq(registry.registered_ids(), ["vendor/demo"])
  let document = match @bootstrap.load_document(path) {
    Err(error) => abort(error)
    Ok(document) => document
  }
  match
    prepare_app(document.manifest(), registry, base_dir=document.base_dir()) {
    Err(error) => abort(error)
    Ok(prepared) => assert_eq(prepared.prepared_extensions().length(), 0)
  }
  @mbfs.remove_file(path) catch {
    _ => ()
  }
}
