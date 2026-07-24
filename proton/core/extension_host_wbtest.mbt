///|
fn expect_extension_host_error(
  action : () -> Unit raise ExtensionHostError,
) -> ExtensionHostError raise {
  try action() catch {
    error => error
  } noraise {
    _ => fail("expected extension host error")
  }
}

///|
test "extension API validation rejects unusable JS properties" {
  assert_eq(
    expect_extension_host_error(() => validate_extension_api_name("demo", "")),
    ExtensionHostError::EmptyApiName(extension_namespace="demo"),
  )
  assert_eq(
    expect_extension_host_error(() => validate_extension_api_name("demo", "  ")),
    ExtensionHostError::EmptyApiName(extension_namespace="demo"),
  )
  assert_eq(
    expect_extension_host_error(() => {
      validate_extension_api_name("demo", "constructor")
    }),
    ExtensionHostError::ReservedApiName(
      extension_namespace="demo",
      api_name="constructor",
    ),
  )
  validate_extension_api_name("demo", "ping")
}

///|
test "extension event validation rejects invalid event targets" {
  assert_eq(
    expect_extension_host_error(() => {
      validate_extension_event_target("", "done")
    }),
    ExtensionHostError::EmptyEventNamespace,
  )
  assert_eq(
    expect_extension_host_error(() => {
      validate_extension_event_target("  ", "done")
    }),
    ExtensionHostError::EmptyEventNamespace,
  )
  assert_eq(
    expect_extension_host_error(() => {
      validate_extension_event_target("demo", "")
    }),
    ExtensionHostError::EmptyEventName(extension_namespace="demo"),
  )
  assert_eq(
    expect_extension_host_error(() => {
      validate_extension_event_target("demo", "  ")
    }),
    ExtensionHostError::EmptyEventName(extension_namespace="demo"),
  )
  validate_extension_event_target("demo", "done")
}

///|
test "extension specs copy mutable array inputs" {
  let dependencies = ["vendor/base"]
  let spec = ExtensionSpec::new(
    "vendor/demo",
    "demo",
    fn(_context) { Extension::new("vendor/demo", "demo", fn(_context) {  }) },
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
  let options = Json::object({ "nested": Json::empty_object() })
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
