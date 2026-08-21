///|
fn expect_config_error(
  action : () -> Unit raise ProjectConfigError,
) -> ProjectConfigError {
  try action() catch {
    error => error
  } noraise {
    _ => abort("expected project config error")
  }
}

///|
test "project config contains only CLI build and package settings" {
  let source =
    #|{
    #|  "backend": { "path": "backend", "package": "app" },
    #|  "frontend": {
    #|    "path": "frontend",
    #|    "dev_url": "http://127.0.0.1:4300",
    #|    "before_dev": "warren dev",
    #|    "before_build": "warren build",
    #|    "dist": "dist"
    #|  },
    #|  "package": {
    #|    "product_name": "Todo",
    #|    "identifier": "com.example.todo",
    #|    "version": "1.2.3",
    #|    "formats": ["app", "zip"],
    #|    "icons": ["icons/app.icns"],
    #|    "resources": ["assets"],
    #|    "output": "dist"
    #|  }
    #|}
  let loaded = load_project_config_from_text(source, "/workspace/todo")
  let config = loaded.config()
  assert_eq(config.backend().unwrap().app_package(), "app")
  let dist = config
    .frontend()
    .unwrap()
    .dist()
    .unwrap()
    .replace_all(old="\\", new="/")
  assert_true(dist.has_suffix("frontend/dist"))
  let package_config = config.package_config().unwrap()
  assert_eq(package_config.product_name, "Todo")
  assert_eq(package_config.version(), "1.2.3")
  assert_eq(package_config.formats(), ["app", "zip"])
  assert_true(package_config.icons()[0].has_suffix("icons/app.icns"))
}

///|
test "project config rejects unknown top-level fields" {
  let source =
    #|{ "window": { "title": "Todo" } }
  let error = expect_config_error(() => {
    ignore(load_project_config_from_text(source, "/workspace/todo"))
  })
  assert_eq(error, UnknownField(path="proton.project.json.window"))
}

///|
test "project config sections must be objects" {
  for section in ["backend", "frontend", "package"] {
    let source = "{ \"" + section + "\": false }"
    let error = expect_config_error(() => {
      ignore(load_project_config_from_text(source, "/workspace/todo"))
    })
    assert_eq(
      error,
      InvalidField(
        path="proton.project.json." + section,
        expectation="must be an object",
      ),
    )
  }
}

///|
test "project paths reject absolute and platform-specific spelling" {
  for
    source in [
      "{ \"backend\": { \"path\": \"/tmp/backend\", \"package\": \"app\" } }", "{ \"frontend\": { \"path\": \"frontend\\\\src\" } }",
    ] {
    ignore(
      expect_config_error(() => {
        ignore(load_project_config_from_text(source, "/workspace/todo"))
      }),
    )
  }
}
