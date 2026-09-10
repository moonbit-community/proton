///|
test "Windows resources use the first ICO and resolve paths from the config" {
  let root = @path.Path(".").resolve().to_string()
  let config = @proton_config.ProjectConfig(
    root,
    "dev.proton.icon-test",
    package_config=Some(
      @proton_config.ProjectPackageConfig("Icon Test", "1.0.0", icons=[
        "icons/app.png", "icons/app.ICO", "icons/other.ico",
      ]),
    ),
  )
  guard windows_app_resource(true, config, None, None) is Some(resource) else {
    fail("expected configured Windows resource")
  }
  assert_eq(resource.icon, @fsutil.resolve_path(root, "icons/app.ICO"))
  assert_eq(
    resource.output_dir,
    @fsutil.resolve_path(root, "target/proton/windows-resources"),
  )
  assert_true(windows_app_resource(false, config, None, None) is None)
  assert_true(windows_app_resource(true, config, Some([]), None) is None)
  let target = @fsutil.resolve_path(root, "isolated build")
  guard windows_app_resource(true, config, Some(["override.ico"]), Some(target))
    is Some(overridden) else {
    fail("expected icon override")
  }
  assert_eq(overridden.icon, @fsutil.resolve_path(root, "override.ico"))
  assert_eq(
    overridden.output_dir,
    @fsutil.path_join(target, "proton/windows-resources"),
  )
}

///|
async test "removing an icon clears the private child build request" {
  let env = app_build_process_env(None)
  assert_eq(env.get("PROTON_WINDOWS_APP_RESOURCE"), Some("null"))
  let configured = app_build_process_env(
    Some({ icon: "C:/icon.ico", output_dir: "C:/build", }),
  )
  guard configured.get("PROTON_WINDOWS_APP_RESOURCE") is Some(request) else {
    fail("expected private build request")
  }
  assert_eq(@json.parse(request), {
    "icon": "C:/icon.ico",
    "output_dir": "C:/build",
  })
}
