///|
test "facade inline extension enables and links framework spec" {
  let app = html("Facade", 900, 700, "<html></html>").extension(
    stub_extension("vendor/demo", js_namespace=Some("demo")),
  )
  @debug.assert_eq(
    app.inline_manifest().extension_setting("vendor/demo"),
    Some(@manifest.ExtensionSetting::enabled()),
  )
  match app.extension_registry() {
    Err(error) => abort(error)
    Ok(registry) => @debug.assert_eq(registry.registered_ids(), ["vendor/demo"])
  }
}

///|
test "facade command enables and registers command spec" {
  let app = html("Facade", 900, 700, "<html></html>").command(
    stub_command_extension("vendor/demo", js_namespace=Some("demo")),
  )
  @debug.assert_eq(
    app.inline_manifest().extension_setting("vendor/demo"),
    Some(@manifest.ExtensionSetting::enabled()),
  )
  match app.command_registry() {
    Err(error) => abort(error)
    Ok(registry) => @debug.assert_eq(registry.registered_ids(), ["vendor/demo"])
  }
}

///|
test "facade command options are preserved" {
  let options = Json::object({ "delay": Json::number(10) })
  let app = html("Facade", 900, 700, "<html></html>").command_with_options(
    stub_command_extension("vendor/demo", js_namespace=Some("demo")),
    options,
  )
  match options {
    Object(object) => object["late"] = Json::boolean(true)
    _ => abort("expected object options")
  }
  match app.inline_manifest().extension_setting("vendor/demo") {
    Some(setting) =>
      match setting.options() {
        Some(Object(object)) => {
          @debug.assert_eq(object.get("delay"), Some(Json::number(10)))
          @debug.assert_eq(object.get("late"), None)
        }
        _ => abort("expected command options")
      }
    None => abort("expected enabled command setting")
  }
}

///|
test "facade duplicate command ids return error" {
  let app = html("Facade", 900, 700, "<html></html>")
    .command(stub_command_extension("vendor/demo", js_namespace=Some("demo")))
    .command(
      stub_command_extension("vendor/demo", js_namespace=Some("demoAgain")),
    )
  match app.command_registry() {
    Err(error) =>
      assert_eq(error, "duplicate command extension id: vendor/demo")
    Ok(_) => abort("expected duplicate command extension id error")
  }
}

///|
test "facade app json link does not auto-enable framework extension" {
  let app = from_file("app.json").link(
    stub_extension("vendor/framework", js_namespace=Some("framework")),
  )
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("File", 900, 700),
    @manifest.AppEntry::Html("<html></html>"),
  )
  @debug.assert_eq(
    app.merge_extension_settings(manifest).extension_setting("vendor/framework"),
    None,
  )
  match app.extension_registry() {
    Err(error) => abort(error)
    Ok(registry) =>
      @debug.assert_eq(registry.registered_ids(), ["vendor/framework"])
  }
}

///|
test "facade app json extension links and enables framework extension" {
  let app = from_file("app.json").extension(
    stub_extension("vendor/framework", js_namespace=Some("framework")),
  )
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("File", 900, 700),
    @manifest.AppEntry::Html("<html></html>"),
  )
  @debug.assert_eq(
    app.merge_extension_settings(manifest).extension_setting("vendor/framework"),
    Some(@manifest.ExtensionSetting::enabled()),
  )
  match app.extension_registry() {
    Err(error) => abort(error)
    Ok(registry) =>
      @debug.assert_eq(registry.registered_ids(), ["vendor/framework"])
  }
}
