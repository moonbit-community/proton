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
    #|  "identifier": "com.example.todo",
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
    #|    "version": "1.2.3",
    #|    "formats": ["app", "zip"],
    #|    "icons": ["icons/app.icns"],
    #|    "prepare": "moon run package/prepare --target native",
    #|    "resources": ["assets"],
    #|    "output": "dist"
    #|  }
    #|}
  let config = load_project_config_from_text(source, "/workspace/todo")
  assert_eq(config.identifier(), "com.example.todo")
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
  assert_eq(
    package_config.prepare(),
    Some("moon run package/prepare --target native"),
  )
}

///|
test "project package decodes platform-specific inputs" {
  let source =
    #|{
    #|  "identifier": "com.example.todo",
    #|  "package": {
    #|    "product_name": "Todo",
    #|    "version": "1.2.3",
    #|    "formats": ["app"],
    #|    "resources": ["assets/common"],
    #|    "sign": { "binaries": ["helpers/common"] },
    #|    "platforms": {
    #|      "macos": {
    #|        "formats": ["app", "dmg"],
    #|        "resources": ["assets/macos"],
    #|        "sign": { "binaries": ["helpers/macos"] }
    #|      },
    #|      "windows": {
    #|        "formats": ["app", "zip", "nsis"],
    #|        "resources": ["assets/windows"]
    #|      },
    #|      "linux": { "formats": [] }
    #|    }
    #|  }
    #|}
  let config = load_project_config_from_text(source, "/workspace/todo")
  let platforms = config.package_config().unwrap().platforms()
  let macos = platforms.macos().unwrap()
  assert_eq(macos.formats(), Some(["app", "dmg"]))
  assert_eq(macos.resources(), [
    @mbpath.Path("/workspace/todo/assets/macos").resolve().to_string(),
  ])
  assert_eq(macos.sign().unwrap().binaries(), [
    @mbpath.Path("/workspace/todo/helpers/macos").resolve().to_string(),
  ])
  assert_eq(
    platforms.windows().unwrap().formats(),
    Some(["app", "zip", "nsis"]),
  )
  assert_eq(platforms.linux().unwrap().formats(), Some([]))
}

///|
test "project package rejects unknown platform overrides" {
  let source =
    #|{
    #|  "identifier": "com.example.todo",
    #|  "package": {
    #|    "product_name": "Todo",
    #|    "version": "1.2.3",
    #|    "platforms": { "android": { "formats": ["app"] } }
    #|  }
    #|}
  let error = expect_config_error(() => {
    ignore(load_project_config_from_text(source, "/workspace/todo"))
  })
  assert_eq(error, UnknownField(path="package.platforms.android"))
}

///|
test "project config rejects unknown top-level fields" {
  let source =
    #|{ "identifier": "com.example.todo", "window": { "title": "Todo" } }
  let error = expect_config_error(() => {
    ignore(load_project_config_from_text(source, "/workspace/todo"))
  })
  assert_eq(error, UnknownField(path="proton.project.json.window"))
}

///|
test "project config requires a valid application identity" {
  let missing = expect_config_error(() => {
    ignore(load_project_config_from_text("{}", "/workspace/todo"))
  })
  assert_eq(missing, MissingField(path="identifier"))
  let invalid = expect_config_error(() => {
    ignore(
      load_project_config_from_text(
        "{ \"identifier\": \"not-an-identifier\" }", "/workspace/todo",
      ),
    )
  })
  assert_eq(
    invalid,
    InvalidField(
      path="identifier",
      expectation="must be a reverse-DNS application identifier",
    ),
  )
}

///|
test "project package cannot define a second application identity" {
  let source =
    #|{
    #|  "identifier": "com.example.todo",
    #|  "package": {
    #|    "product_name": "Todo",
    #|    "identifier": "com.example.other",
    #|    "version": "1.0.0"
    #|  }
    #|}
  let error = expect_config_error(() => {
    ignore(load_project_config_from_text(source, "/workspace/todo"))
  })
  assert_eq(error, UnknownField(path="package.identifier"))
}

///|
test "project config sections must be objects" {
  for section in ["backend", "frontend", "package"] {
    let source = "{ \"identifier\": \"com.example.todo\", \"" +
      section +
      "\": false }"
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
      "{ \"identifier\": \"com.example.todo\", \"backend\": { \"path\": \"/tmp/backend\", \"package\": \"app\" } }",
      "{ \"identifier\": \"com.example.todo\", \"frontend\": { \"path\": \"frontend\\\\src\" } }",
    ] {
    ignore(
      expect_config_error(() => {
        ignore(load_project_config_from_text(source, "/workspace/todo"))
      }),
    )
  }
}
