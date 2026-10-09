///|
async test "loaded configuration remains a complete independent snapshot" {
  let dir = @async_fs.tmpdir(prefix="proton-config-")
  defer @async_fs.rmdir(dir, recursive=true)
  let path = @mbpath.Path(dir).join("proton.project.json").to_string()
  let source =
    #|{"identifier":"com.example.snapshot","backend":{"path":"backend","package":"app"},"frontend":{"path":"frontend","dev_url":"http://localhost:4300","dist":"dist"},"package":{"product_name":"Snapshot","version":"1.2.3","resources":["assets"],"platforms":{"macos":{"resources":["mac-assets"]}}}}
  @async_fs.write_file(path, source, create_mode=CreateOrTruncate)
  let previous = @env.get_env_var("PROTON_PROJECT_CONFIG")
  @env.set_env_var("PROTON_PROJECT_CONFIG", path)
  defer (match previous {
    Some(value) => @env.set_env_var("PROTON_PROJECT_CONFIG", value)
    None => @env.unset_env_var("PROTON_PROJECT_CONFIG")
  })
  let app = html("Test", "").load_config()
  assert_true(app.validation_errors.is_empty())
  @async_fs.remove(path)
  assert_eq(app.name(), "Snapshot")
  assert_eq(app.version(), "1.2.3")
  assert_eq(app.application_identifier(), "com.example.snapshot")
  let snapshot = app.config()
  assert_eq(snapshot.backend.unwrap().path, "backend")
  assert_eq(snapshot.frontend.unwrap().dev_url, Some("http://localhost:4300"))
  assert_eq(snapshot.frontend.unwrap().dist, Some("dist"))
  snapshot.package_config.unwrap().resources.push("changed")
  snapshot.package_config.unwrap().platforms.macos.unwrap().resources.clear()
  assert_eq(app.config().package_config.unwrap().resources, ["assets"])
  assert_eq(
    app.config().package_config.unwrap().platforms.macos.unwrap().resources,
    ["mac-assets"],
  )
}

///|
test "explicit configuration is copied and conflicts with another identity" {
  let config = AppConfig(
    "com.example.explicit",
    package_config=Some(
      PackageConfig("Explicit", "1.0.0", resources=["assets"]),
    ),
  )
  let app = html("Test", "").with_config(config)
  config.package_config.unwrap().resources.clear()
  assert_eq(app.config().package_config.unwrap().resources, ["assets"])
  ignore(app.identifier("com.example.other"))
  assert_eq(app.application_identifier(), "com.example.explicit")
  assert_eq(app.validation_errors.length(), 1)
}

///|
test "invalid explicit configuration keeps its diagnostic" {
  let app = html("Test", "").with_config(AppConfig("invalid"))
  assert_eq(app.validation_errors.length(), 1)
  try app.config() catch {
    @proton_config.InvalidField(path="identifier", ..) => ()
    _ => fail("expected original identity diagnostic")
  } noraise {
    _ => fail("expected config to fail")
  }
}

///|
async test "explicit configuration must match bundled identity" {
  let executable = @mbpath.Path(@env.args()[0]).resolve()
  let directory = if @mbpath.sep == '\\' {
    executable.dirname()
  } else {
    executable.dirname().join("../Resources").normalize()
  }
  let created_directory = !(@mbfs.is_dir(directory.to_string()) catch {
      _ => false
    })
  if created_directory {
    @async_fs.mkdir(directory.to_string())
  }
  defer (if created_directory { @async_fs.rmdir(directory.to_string()) })
  let path = directory.join("proton-package.json").to_string()
  assert_false(@mbfs.is_file(path) catch { _ => false })
  @async_fs.write_file(
    path,
    AppConfig("com.example.packaged").to_json().stringify(),
    create_mode=CreateOrTruncate,
  )
  defer @async_fs.remove(path)
  let matching = html("Test", "").with_config(AppConfig("com.example.packaged"))
  assert_true(matching.validation_errors.is_empty())
  let mismatching = html("Test", "").with_config(AppConfig("com.example.other"))
  assert_eq(mismatching.validation_errors.length(), 1)
  assert_true(
    mismatching.validation_errors[0].message().contains("com.example.packaged"),
  )
  try mismatching.config() catch {
    @proton_config.InvalidField(path="identifier", ..) => ()
    _ => fail("expected bundled identity diagnostic")
  } noraise {
    _ => fail("mismatching configuration must not be installed")
  }
}
