///|
test "facade inline extension enables and links framework spec" {
  let app = html("Facade", "<html></html>", width=900, height=700).extension(
    @lepus_extension.from_core_spec(
      stub_extension("vendor/demo", js_namespace=Some("demo")),
    ),
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
  let app = html("Facade", "<html></html>", width=900, height=700).extension(
    @lepus_extension.from_command_spec(
      stub_command_extension("vendor/demo", js_namespace=Some("demo")),
    ),
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
  let app = html("Facade", "<html></html>", width=900, height=700).extension(
    @lepus_extension.from_command_spec(
      stub_command_extension("vendor/demo", js_namespace=Some("demo")),
    ),
    options~,
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
  let app = html("Facade", "<html></html>", width=900, height=700)
    .extension(
      @lepus_extension.from_command_spec(
        stub_command_extension("vendor/demo", js_namespace=Some("demo")),
      ),
    )
    .extension(
      @lepus_extension.from_command_spec(
        stub_command_extension("vendor/demo", js_namespace=Some("demoAgain")),
      ),
    )
  match app.command_registry() {
    Err(error) =>
      assert_eq(error, "duplicate command extension id: vendor/demo")
    Ok(_) => abort("expected duplicate command extension id error")
  }
}

///|
test "facade duplicate framework extension with same options deduplicates" {
  let app = html("Facade", "<html></html>", width=900, height=700)
    .extension(
      @lepus_extension.from_core_spec(
        stub_extension("vendor/demo", js_namespace=Some("demo")),
      ),
    )
    .extension(
      @lepus_extension.from_core_spec(
        stub_extension("vendor/demo", js_namespace=Some("demo")),
      ),
    )
  match app.extension_registry() {
    Err(error) => abort(error)
    Ok(registry) => @debug.assert_eq(registry.registered_ids(), ["vendor/demo"])
  }
}

///|
test "facade duplicate extension id with different options returns error" {
  let app = html("Facade", "<html></html>", width=900, height=700)
    .extension(
      @lepus_extension.from_core_spec(
        stub_extension("vendor/demo", js_namespace=Some("demo")),
      ),
      options=Json::object({ "mode": Json::string("a") }),
    )
    .extension(
      @lepus_extension.from_core_spec(
        stub_extension("vendor/demo", js_namespace=Some("demo")),
      ),
      options=Json::object({ "mode": Json::string("b") }),
    )
  match app.extension_registry() {
    Err(error) =>
      assert_eq(
        error, "duplicate extension id with different options: vendor/demo",
      )
    Ok(_) => abort("expected duplicate extension options error")
  }
}

///|
test "facade app json extension links and enables framework extension" {
  let app = config("app.json").extension(
    @lepus_extension.from_core_spec(
      stub_extension("vendor/framework", js_namespace=Some("framework")),
    ),
  )
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("File", 900, 700),
    @manifest.AppEntry::Html("<html></html>"),
  )
  @debug.assert_eq(
    app.merge_config(manifest).extension_setting("vendor/framework"),
    Some(@manifest.ExtensionSetting::enabled()),
  )
  match app.extension_registry() {
    Err(error) => abort(error)
    Ok(registry) =>
      @debug.assert_eq(registry.registered_ids(), ["vendor/framework"])
  }
}

///|
test "facade config ignores extension settings from app json manifest" {
  let app = config("app.json").extension(
    @lepus_extension.from_core_spec(
      stub_extension("vendor/code", js_namespace=Some("code")),
    ),
  )
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("File", 900, 700),
    @manifest.AppEntry::Html("<html></html>"),
    extensions={ "vendor/config": @manifest.ExtensionSetting::enabled() },
  )
  let merged = app.merge_config(manifest)
  @debug.assert_eq(merged.extension_setting("vendor/config"), None)
  @debug.assert_eq(
    merged.extension_setting("vendor/code"),
    Some(@manifest.ExtensionSetting::enabled()),
  )
}
