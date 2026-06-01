///|
test "extension API validation rejects unusable JS properties" {
  match validate_extension_api_name("demo", "") {
    Err(error) =>
      assert_eq(
        error, "ExtensionContext::register_api: API name must not be empty: demo",
      )
    Ok(_) => abort("expected empty extension API name error")
  }
  match validate_extension_api_name("demo", "  ") {
    Err(error) =>
      assert_eq(
        error, "ExtensionContext::register_api: API name must not be empty: demo",
      )
    Ok(_) => abort("expected blank extension API name error")
  }
  match validate_extension_api_name("demo", "constructor") {
    Err(error) =>
      assert_eq(
        error, "ExtensionContext::register_api: reserved API name: demo.constructor",
      )
    Ok(_) => abort("expected reserved extension API name error")
  }
  match validate_extension_api_name("demo", "ping") {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}

///|
test "extension event validation rejects invalid event targets" {
  match validate_extension_event_target("", "done") {
    Err(error) =>
      assert_eq(error, "extension event namespace must not be empty")
    Ok(_) => abort("expected empty extension event namespace error")
  }
  match validate_extension_event_target("  ", "done") {
    Err(error) =>
      assert_eq(error, "extension event namespace must not be empty")
    Ok(_) => abort("expected blank extension event namespace error")
  }
  match validate_extension_event_target("demo", "") {
    Err(error) =>
      assert_eq(error, "extension event name must not be empty: demo")
    Ok(_) => abort("expected empty extension event name error")
  }
  match validate_extension_event_target("demo", "  ") {
    Err(error) =>
      assert_eq(error, "extension event name must not be empty: demo")
    Ok(_) => abort("expected blank extension event name error")
  }
  match validate_extension_event_target("demo", "done") {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}

///|
test "extension specs copy mutable array inputs" {
  let dependencies = ["vendor/base"]
  let spec = ExtensionSpec::new(
    "vendor/demo",
    "demo",
    fn(_context) {
      Ok(Extension::new("vendor/demo", "demo", fn(_context) {  }))
    },
    dependencies~,
  )
  dependencies.push("vendor/mutated")
  @debug.assert_eq(spec.dependencies(), ["vendor/base"])
  let exposed_dependencies = spec.dependencies()
  exposed_dependencies.push("vendor/changed")
  @debug.assert_eq(spec.dependencies(), ["vendor/base"])

  let scripts = ["window.__demo = true;"]
  let extension = Extension::new(
    "vendor/demo",
    "demo",
    fn(_context) {  },
    scripts~,
  )
  scripts.push("window.__demo = false;")
  assert_eq(extension.scripts().length(), 1)
  let exposed_scripts = extension.scripts()
  exposed_scripts.push("window.__demo = 'changed';")
  assert_eq(extension.scripts().length(), 1)
}

///|
test "extension build context exposes option snapshots" {
  let options = Json::object({ "nested": Json::object({}) })
  let context = ExtensionBuildContext::new(options=Some(options))
  match options {
    Object(object) => object["late"] = Json::boolean(true)
    _ => abort("expected object options")
  }
  match context.options() {
    Some(Object(object)) => {
      @debug.assert_eq(object.get("late"), None)
      object["exposed"] = Json::boolean(true)
    }
    _ => abort("expected context object options")
  }
  match context.options() {
    Some(Object(object)) => @debug.assert_eq(object.get("exposed"), None)
    _ => abort("expected fresh context object options")
  }
}
