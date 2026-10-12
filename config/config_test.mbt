///|
fn expect_config_error(
  action : () -> Unit raise @proton_config.AppConfigError,
) -> @proton_config.AppConfigError {
  try action() catch {
    error => error
  } noraise {
    _ => abort("expected project config error")
  }
}

///|
test "application config preserves all fields and relative paths" {
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
  let config = @proton_config.AppConfig::parse(source)
  assert_eq(config.identifier, "com.example.todo")
  assert_eq(config.backend.unwrap().app_package, "app")
  let dist = config.frontend.unwrap().dist
    .unwrap()
    .replace_all(old="\\", new="/")
  assert_eq(dist, "dist")
  let package_config = config.package_config.unwrap()
  assert_eq(package_config.product_name, "Todo")
  assert_eq(package_config.version, "1.2.3")
  assert_eq(package_config.formats, ["app", "zip"])
  assert_true(
    package_config.icons[0]
    .replace_all(old="\\", new="/")
    .has_suffix("icons/app.icns"),
  )
  assert_eq(
    package_config.prepare,
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
    #|        "minimum_system_version": "15.0",
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
  let config = @proton_config.AppConfig::parse(source)
  let platforms = config.package_config.unwrap().platforms
  let macos = platforms.macos.unwrap()
  assert_eq(macos.minimum_system_version, Some("15.0"))
  assert_eq(macos.formats, Some(["app", "dmg"]))
  assert_eq(macos.resources, ["assets/macos"])
  assert_eq(macos.sign.unwrap().binaries, ["helpers/macos"])
  assert_eq(platforms.windows.unwrap().formats, Some(["app", "zip", "nsis"]))
  assert_eq(platforms.linux.unwrap().formats, Some([]))
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
    ignore(@proton_config.AppConfig::parse(source))
  })
  assert_eq(error, UnknownField(path="package.platforms.android"))
}

///|
test "NSIS install modes belong only to the Windows package configuration" {
  for mode in ["currentUser", "perMachine", "both"] {
    let config = @proton_config.AppConfig::decode({
      "identifier": "com.example.demo",
      "package": {
        "product_name": "Demo",
        "version": "1.0.0",
        "platforms": { "windows": { "nsis_install_mode": mode } },
      },
    })
    assert_eq(
      config.package_config.unwrap().platforms.windows.unwrap().nsis_install_mode,
      Some(mode),
    )
  }
  let invalid = expect_config_error(() => {
    ignore(
      @proton_config.AppConfig::decode({
        "identifier": "com.example.demo",
        "package": {
          "product_name": "Demo",
          "version": "1.0.0",
          "platforms": { "windows": { "nsis_install_mode": "admin" } },
        },
      }),
    )
  })
  assert_eq(
    invalid,
    UnsupportedValue(
      path="package.platforms.windows.nsis_install_mode",
      value="admin",
    ),
  )
  for platform in ["macos", "linux"] {
    let platforms : Map[String, Json] = Map([])
    platforms[platform] = { "nsis_install_mode": "perMachine" }
    let invalid = expect_config_error(() => {
      ignore(
        @proton_config.AppConfig::decode({
          "identifier": "com.example.demo",
          "package": {
            "product_name": "Demo",
            "version": "1.0.0",
            "platforms": platforms.to_json(),
          },
        }),
      )
    })
    assert_eq(
      invalid,
      UnknownField(path="package.platforms." + platform + ".nsis_install_mode"),
    )
  }
}

///|
test "project config rejects unknown top-level fields" {
  let source =
    #|{ "identifier": "com.example.todo", "window": { "title": "Todo" } }
  let error = expect_config_error(() => {
    ignore(@proton_config.AppConfig::parse(source))
  })
  assert_eq(error, UnknownField(path="proton.project.json.window"))
}

///|
test "project config requires a valid application identity" {
  let missing = expect_config_error(() => {
    ignore(@proton_config.AppConfig::parse("{}"))
  })
  assert_true(missing.message().contains("identifier"))
  let invalid = expect_config_error(() => {
    ignore(
      @proton_config.AppConfig::parse(
        "{ \"identifier\": \"not-an-identifier\" }",
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
    ignore(@proton_config.AppConfig::parse(source))
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
      ignore(@proton_config.AppConfig::parse(source))
    })
    assert_true(error.message().contains(section))
  }
}
