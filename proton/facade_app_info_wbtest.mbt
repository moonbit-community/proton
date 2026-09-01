///|
test "packaged application metadata exposes product name and version" {
  let source =
    #|{
    #|  "schema_version": 1,
    #|  "product_name": "Proton Notes",
    #|  "version": "1.2.3"
    #|}
    #|
  let metadata = packaged_application_metadata_from_json(source)
  assert_eq(metadata.name, "Proton Notes")
  assert_eq(metadata.version, "1.2.3")
}

///|
test "packaged application metadata requires non-empty fields" {
  try
    packaged_application_metadata_from_json(
      "{\"product_name\":\"Proton Notes\",\"version\":\"  \"}",
    )
  catch {
    MissingField(field="version") => ()
    _ => fail("expected the version field to be rejected")
  } noraise {
    _ => fail("expected packaged metadata validation to fail")
  }
}

///|
test "project application metadata uses package configuration" {
  let config = @proton_config.ProjectConfig(
    "/workspace/notes",
    "dev.proton.notes",
    package_config=Some(
      @proton_config.ProjectPackageConfig("  Proton Notes  ", " 1.2.3 "),
    ),
  )
  let metadata = project_application_metadata(config)
  assert_eq(metadata.name, "Proton Notes")
  assert_eq(metadata.version, "1.2.3")
}

///|
test "packaged resource roots follow each bundle layout" {
  assert_eq(
    normalize_path_separators(
      packaged_resource_dir_from_manifest(
        "/Applications/Notes.app/Contents/Resources/proton-package.json", false,
      ),
    ),
    "/Applications/Notes.app/Contents/Resources",
  )
  assert_eq(
    normalize_path_separators(
      packaged_resource_dir_from_manifest(
        "/opt/Notes/proton-package.json", true,
      ),
    ),
    "/opt/Notes/Resources",
  )
}

///|
test "project application metadata requires package configuration" {
  let config = @proton_config.ProjectConfig(
    "/workspace/notes", "dev.proton.notes",
  )
  try project_application_metadata(config) catch {
    MissingPackageMetadata => ()
    _ => fail("expected missing package metadata")
  } noraise {
    _ => fail("expected project metadata validation to fail")
  }
}

///|
test "standard home and application data roots follow platform conventions" {
  assert_eq(
    normalize_path_separators(
      home_dir_for_platform("windows", None, Some("C:/Users/test")),
    ),
    "C:/Users/test",
  )
  assert_eq(
    normalize_path_separators(
      application_data_root_for_platform(
        "macos",
        Some("/Users/test"),
        None,
        None,
      ),
    ),
    "/Users/test/Library/Application Support",
  )
  assert_eq(
    normalize_path_separators(
      application_data_root_for_platform(
        "windows",
        None,
        Some("C:/Users/test/AppData/Roaming"),
        None,
      ),
    ),
    "C:/Users/test/AppData/Roaming",
  )
  assert_eq(
    normalize_path_separators(
      application_data_root_for_platform(
        "linux",
        Some("/home/test"),
        None,
        Some("/config"),
      ),
    ),
    "/config",
  )
  assert_eq(
    normalize_path_separators(
      application_data_root_for_platform(
        "linux",
        Some("/home/test"),
        None,
        None,
      ),
    ),
    "/home/test/.config",
  )
}

///|
test "temporary path resolution uses platform environment precedence" {
  assert_eq(
    normalize_path_separators(
      temp_dir_for_platform(
        "windows",
        None,
        Some("C:/Temp"),
        Some("C:/Fallback"),
      ),
    ),
    "C:/Temp",
  )
  assert_eq(
    temp_dir_for_platform("macos", Some("/private/tmp/app"), None, None),
    "/private/tmp/app",
  )
  assert_eq(temp_dir_for_platform("linux", None, None, None), "/tmp")
}

///|
test "application root and packaged state share the package manifest probe" {
  assert_eq(app_path(), resource_dir())
  assert_eq(is_packaged(), packaged_application_manifest_path() is Some(_))
}

///|
test "platform-specific standard paths report availability" {
  let app = html("Paths", "<main>Paths</main>")
  let platform = @native.runtime_info().platform
  if platform == "macos" {
    try app.path(AppPathKind::Assets) catch {
      UnsupportedPath(kind="assets", platform="macos") => ()
      _ => fail("expected assets to be unavailable on macOS")
    } noraise {
      _ => fail("expected assets lookup to fail on macOS")
    }
  } else {
    let assets : @mbpath.Path = app.path(AppPathKind::Assets)
    assert_true(assets.is_absolute())
  }
  if platform == "windows" {
    let recent : @mbpath.Path = app.path(AppPathKind::Recent)
    assert_true(recent.is_absolute())
  } else {
    try app.path(AppPathKind::Recent) catch {
      UnsupportedPath(kind="recent", platform=_) => ()
      _ => fail("expected recent to be unavailable outside Windows")
    } noraise {
      _ => fail("expected recent lookup to fail outside Windows")
    }
  }
}

///|
test "path overrides preserve dependent application paths" {
  let app = html("Paths", "<main>Paths</main>").identifier(
    "dev.proton.path-overrides",
  )
  let root = app.path(AppPathKind::Temp)
  let overridden = app.set_path(AppPathKind::UserData, root)
  assert_eq(overridden.path(AppPathKind::UserData), root)
  assert_eq(overridden.data_dir(), root)
  assert_eq(
    overridden.path(AppPathKind::SessionData),
    @mbpath.Path(root).join("browser").normalize().to_string(),
  )
}

///|
test "session data overrides are consumed by single-instance runtime config" {
  let app = html("Paths", "<main>Paths</main>")
    .identifier("dev.proton.session-override")
    .single_instance()
  let root = app.path(AppPathKind::Temp)
  let app = app.set_path(AppPathKind::SessionData, root)
  assert_eq(
    resolve_browser_data_dir(app, app.resolved_app_config()),
    Some(root),
  )
}

///|
test "application log path supports custom and Electron defaults" {
  let custom = html("Paths", "<main>Paths</main>").identifier(
    "dev.proton.log-override",
  )
  let temp = custom.path(AppPathKind::Temp)
  let custom_path = @mbpath.Path(temp)
    .join("proton-custom-log-path")
    .normalize()
    .to_string()
  let custom = custom.set_app_logs_path(path=custom_path)
  assert_eq(custom.path(AppPathKind::Logs), custom_path)
  assert_true(custom.create_logs_path)

  let defaults = html("Paths", "<main>Paths</main>")
    .identifier("dev.proton.default-logs")
    .set_path(AppPathKind::UserData, temp)
    .set_app_logs_path()
  let platform = @native.runtime_info().platform
  let expected = if platform == "macos" {
    app_log_dir_for_platform(
      platform,
      "dev.proton.default-logs",
      @env.get_env_var("HOME"),
      @env.get_env_var("LOCALAPPDATA"),
      @env.get_env_var("XDG_STATE_HOME"),
    )
  } else {
    @mbpath.Path(temp).join("logs").normalize().to_string()
  }
  assert_eq(defaults.path(AppPathKind::Logs), expected)
}

///|
test "path overrides reject relative and missing paths" {
  let app = html("Paths", "<main>Paths</main>")
  try app.set_path(AppPathKind::Home, "relative/path") catch {
    InvalidPathOverride(kind="home", reason="path must be absolute", ..) => ()
    _ => fail("expected a relative path validation error")
  } noraise {
    _ => fail("expected relative path override to fail")
  }
  let missing = @mbpath.Path(app.path(AppPathKind::Executable))
    .join("missing-path")
    .to_string()
  try app.set_path(AppPathKind::Home, missing) catch {
    InvalidPathOverride(kind="home", reason="path does not exist", ..) => ()
    _ => fail("expected a missing path validation error")
  } noraise {
    _ => fail("expected missing path override to fail")
  }
  let executable = app.path(AppPathKind::Executable)
  try app.set_path(AppPathKind::Home, executable) catch {
    InvalidPathOverride(kind="home", reason="path is not a directory", ..) => ()
    _ => fail("expected a directory path validation error")
  } noraise {
    _ => fail("expected file-backed directory override to fail")
  }
}
