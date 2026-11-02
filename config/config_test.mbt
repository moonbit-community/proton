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
test "root overrides resolve all project sections without mutating the source" {
  let source : Json = {
    "identifier": "com.example.todo",
    "backend": { "path": ".", "package": "app" },
    "frontend": {
      "path": "frontend",
      "before_build": "../tools/warren build",
      "dist": "dist",
    },
    "package": {
      "product_name": "Todo",
      "version": "1.2.3",
      "formats": ["app"],
      "resources": ["assets/common"],
      "sign": { "binaries": ["helpers/common"] },
    },
    "platforms": {
      "macos": {
        "package": {
          "minimum_system_version": "15.0",
          "formats": ["app", "dmg"],
          "resources": ["assets/macos"],
          "sign": { "binaries": ["helpers/macos"] },
        },
      },
      "windows": {
        "backend": { "package": "windows-app" },
        "frontend": { "before_build": "..\\tools\\warren.exe build" },
        "package": { "nsis_install_mode": "both", "resources": [] },
      },
      "linux": { "package": { "formats": [] } },
    },
  }
  let mac = @proton_config.AppConfig::decode(source, platform=Macos)
  let package_config = mac.package_config.unwrap()
  assert_eq(package_config.minimum_system_version, Some("15.0"))
  assert_eq(package_config.formats, ["app", "dmg"])
  assert_eq(package_config.resources, ["assets/macos"])
  assert_eq(package_config.sign.unwrap().binaries, ["helpers/macos"])
  let win = @proton_config.AppConfig::decode(source, platform=Windows)
  assert_eq(win.backend.unwrap().path, ".")
  assert_eq(win.backend.unwrap().app_package, "windows-app")
  assert_eq(win.frontend.unwrap().path, Some("frontend"))
  assert_eq(
    win.frontend.unwrap().before_build,
    Some("..\\tools\\warren.exe build"),
  )
  assert_eq(win.package_config.unwrap().nsis_install_mode, Some("both"))
  assert_eq(win.package_config.unwrap().resources, [])
  let linux = @proton_config.AppConfig::decode(source, platform=Linux)
  assert_eq(linux.package_config.unwrap().formats, [])
  assert_eq(linux.package_config.unwrap().resources, ["assets/common"])
  assert_eq(linux.backend.unwrap().app_package, "app")
  assert_eq(@proton_config.AppConfig::decode(source, platform=Macos), mac)
  assert_eq(
    @proton_config.AppConfig::decode(mac.to_json(), platform=Macos),
    mac,
  )
  assert_eq(
    @proton_config.AppConfig::decode(win.to_json(), platform=Windows),
    win,
  )
}

///|
test "platform null clears optional fields and omitted fields inherit" {
  let config = @proton_config.AppConfig::decode(
    {
      "identifier": "com.example.todo",
      "frontend": {
        "path": "ui",
        "before_build": "warren build",
        "dev_url": "http://localhost:4300",
      },
      "package": {
        "product_name": "Todo",
        "version": "1.0.0",
        "prepare": "echo prepare",
        "sign": { "binaries": ["helper"] },
      },
      "platforms": {
        "windows": {
          "frontend": { "before_build": null },
          "package": { "prepare": null, "sign": null },
        },
      },
    },
    platform=Windows,
  )
  assert_eq(config.frontend.unwrap().before_build, None)
  assert_eq(config.frontend.unwrap().path, Some("ui"))
  assert_eq(config.frontend.unwrap().dev_url, Some("http://localhost:4300"))
  assert_eq(config.package_config.unwrap().prepare, None)
  assert_eq(config.package_config.unwrap().sign, None)
}

///|
test "platform overrides reject unknown fields and identity changes" {
  let cases : Array[(Json, String)] = [
    ({ "android": {} }, "platforms.android"),
    (
      { "windows": { "identifier": "com.example.other" } },
      "platforms.windows.identifier",
    ),
    (
      { "windows": { "package": { "version": "2.0.0" } } },
      "platforms.windows.package.version",
    ),
    ({ "windows": { "platforms": {} } }, "platforms.windows.platforms"),
    (
      { "macos": { "package": { "nsis_install_mode": "both" } } },
      "platforms.macos.package.nsis_install_mode",
    ),
    (
      { "linux": { "package": { "minimum_system_version": "15.0" } } },
      "platforms.linux.package.minimum_system_version",
    ),
    (
      { "windows": { "package": { "sign": { "unknown": [] } } } },
      "platforms.windows.package.sign.unknown",
    ),
  ]
  for (patch, field) in cases {
    let error = expect_config_error(() => {
      ignore(
        @proton_config.AppConfig::decode({
          "identifier": "com.example.todo",
          "platforms": patch,
        }),
      )
    })
    assert_eq(error, UnknownField(path=field))
  }
}

///|
test "legacy package platforms reports the new location" {
  let error = expect_config_error(() => {
    ignore(
      @proton_config.AppConfig::decode({
        "identifier": "com.example.todo",
        "package": {
          "product_name": "Todo",
          "version": "1.0.0",
          "platforms": {},
        },
      }),
    )
  })
  assert_true(error.message().contains("root platforms.<platform>.package"))
}

///|
test "invalid inactive platforms and required-field clearing are rejected" {
  let patches : Array[Json] = [
    { "package": { "nsis_install_mode": "admin" } },
    { "package": { "product_name": null } },
    { "package": { "resources": null } },
    { "frontend": { "before_build": 42 } },
    { "frontend": { "path": "" } },
  ]
  for patch in patches {
    ignore(
      expect_config_error(() => {
        ignore(
          @proton_config.AppConfig::decode(
            {
              "identifier": "com.example.todo",
              "package": { "product_name": "Todo", "version": "1.0.0" },
              "platforms": { "windows": patch },
            },
            platform=Linux,
          ),
        )
      }),
    )
  }
}

///|
test "NSIS install modes remain typed Windows package settings" {
  for mode in ["currentUser", "perMachine", "both"] {
    let config = @proton_config.AppConfig::decode(
      {
        "identifier": "com.example.demo",
        "package": { "product_name": "Demo", "version": "1.0.0" },
        "platforms": { "windows": { "package": { "nsis_install_mode": mode } } },
      },
      platform=Windows,
    )
    assert_eq(config.package_config.unwrap().nsis_install_mode, Some(mode))
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

///|
test "signing inputs accept exact paths and dir/** trees only" {
  let config = @proton_config.AppConfig::decode(
    {
      "identifier": "com.example.tree",
      "package": {
        "product_name": "Tree",
        "version": "1.0.0",
        "sign": { "binaries": ["payload/**", "bin/tool"] },
      },
    },
    platform=Macos,
  )
  assert_eq(config.package_config.unwrap().sign.unwrap().binaries, [
    "payload/**", "bin/tool",
  ])
  for glob in ["payload/*.dylib", "payload/**/tool", "**"] {
    let error = expect_config_error(() => {
      ignore(
        @proton_config.AppConfig::decode({
          "identifier": "com.example.tree",
          "package": {
            "product_name": "Tree",
            "version": "1.0.0",
            "sign": { "binaries": [glob] },
          },
        }),
      )
    })
    assert_eq(
      error,
      InvalidField(
        path="package.sign.binaries",
        expectation="must be exact paths or dir/** trees",
      ),
    )
  }
}
