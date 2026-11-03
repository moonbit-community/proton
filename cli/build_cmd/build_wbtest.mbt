///|
fn parse_build_args(args : Array[String]) -> RawBuildOptions raise {
  build_options_from_matches(command().parse(argv=args, env=Map([])))
}

///|
fn[T] expect_build_error_message(action : () -> T raise) -> String raise {
  try action() catch {
    error => Show::to_string(error)
  } noraise {
    _ => fail("expected build error")
  }
}

///|
test "parse build args defaults and moon args" {
  let raw = parse_build_args(["--", "--warn-list", "+a"])
  @debug.assert_eq(raw.app_package, None)
  @debug.assert_eq(raw.config_path, None)
  @debug.assert_eq(raw.moon_target_dir, None)
  @debug.assert_eq(raw.icons, None)
  @debug.assert_eq(raw.run_frontend_build, true)
  @debug.assert_eq(raw.moon_args, ["--warn-list", "+a"])
}

///|
test "moon build options require the separator" {
  try parse_build_args(["--warn-list", "+a"]) catch {
    error =>
      assert_true(
        error.to_string().contains("unexpected argument '--warn-list'"),
      )
  } noraise {
    _ => fail("expected argparse to reject a moon option before --")
  }
}

///|
test "parse build args package and config" {
  let raw = parse_build_args([
    "--package", "desktop", "--config", "config/proton.project.json", "--no-frontend",
  ])
  @debug.assert_eq(raw.app_package, Some("desktop"))
  @debug.assert_eq(raw.config_path, Some("config/proton.project.json"))
  @debug.assert_eq(raw.run_frontend_build, false)
}

///|
test "parse build args accepts an isolated Moon target directory" {
  let raw = parse_build_args([
    "--package", "app", "--moon-target-dir", "custom-build",
  ])
  @debug.assert_eq(raw.moon_target_dir, Some("custom-build"))
}

///|
test "parse build args keeps dash-leading config paths behind --config=" {
  let error = expect_build_error_message(() => {
    parse_build_args(["--config", "-custom.proton"])
  })
  assert_true(error.contains("a value is required for '--config'"))
  let raw = parse_build_args(["--config=-custom.proton"])
  @debug.assert_eq(raw.config_path, Some("-custom.proton"))
}

///|
test "parse build args rejects moon target override" {
  let first = expect_build_error_message(() => {
    parse_build_args([
      "--package", "app", "--", "--diagnostic-limit", "80", "--target", "wasm-gc",
    ])
  })
  assert_true(first.contains("always uses --target native"))
  let second = expect_build_error_message(() => {
    parse_build_args(["--package", "app", "--", "--target=wasm-gc"])
  })
  assert_true(second.contains("always uses --target native"))
}

///|
test "moon build args append native target" {
  @debug.assert_eq(moon_build_args("app", ["--diagnostic-limit", "80"]), [
    "build", "app", "--diagnostic-limit", "80", "--target", "native",
  ])
}

///|
test "moon build args prepend an isolated target directory" {
  @debug.assert_eq(
    moon_build_args_with_target_dir(
      "app",
      ["--diagnostic-limit", "80"],
      Some("custom-build"),
    ),
    [
      "--target-dir", "custom-build", "build", "app", "--diagnostic-limit", "80",
      "--target", "native",
    ],
  )
}

///|
test "moon build-only args select the requested build mode" {
  @debug.assert_eq(moon_build_only_args("app", false), [
    "run", "app", "--target", "native", "--debug", "--build-only",
  ])
  @debug.assert_eq(moon_build_only_args("desktop", true), [
    "run", "desktop", "--target", "native", "--release", "--build-only",
  ])
}

///|
test "moon build-only output identifies one executable" {
  assert_eq(
    artifact_path_from_build_output(
      "{\"artifacts_path\":[\"/tmp/build/app.exe\"]}\n",
    ),
    "/tmp/build/app.exe",
  )
}

///|
test "moon build-only output rejects missing or ambiguous artifacts" {
  for
    output in [
      "{}", "{\"artifacts_path\":[]}", "{\"artifacts_path\":[\"first.exe\",\"second.exe\"]}",
      "{\"artifacts_path\":[1]}",
    ] {
    let error = expect_build_error_message(() => {
      artifact_path_from_build_output(output)
    })
    assert_true(error.contains("returned invalid output"))
  }
}

///|
test "native Moon commands select a source-built runtime on Unix" {
  @debug.assert_eq(native_moon_process_env_for(false, false, None), {
    "MOON_CC": "cc",
  })
  @debug.assert_eq(native_moon_process_env_for(false, false, Some("gcc")), {
    "MOON_CC": "gcc",
  })
  @debug.assert_eq(native_moon_process_env_for(false, false, Some("clang")), {
    "MOON_CC": "clang",
  })
  @debug.assert_eq(native_moon_process_env_for(true, false, None), Map([]))
}

///|
test "native Moon commands target macOS 12" {
  @debug.assert_eq(native_moon_process_env_for(false, true, None), {
    "MACOSX_DEPLOYMENT_TARGET": "12.0",
    "MOON_CC": "cc",
  })
}

///|
test "frontend release requires dist" {
  let config = @proton_config.AppConfig(
    "com.example.test",
    frontend=Some(
      @proton_config.FrontendConfig(before_build=Some("npm run build")),
    ),
  )
  let error = expect_build_error_message(() => validate_release_config(config))
  assert_true(error.contains("frontend.dist is required"))
}

///|
async test "project resolution does not require frontend build output" {
  let config = @proton_config.AppConfig(
    "com.example.test",
    frontend=Some(
      @proton_config.FrontendConfig(dist=Some("missing-frontend-dist")),
    ),
  )
  let invocation = project_build_invocation(".", { base_dir: ".", config, }, RawBuildOptions::{
    app_package: None,
    config_path: None,
    moon_target_dir: None,
    icons: None,
    run_frontend_build: false,
    moon_args: [],
  })
  @debug.assert_eq(invocation.backend_path, ".")
  @debug.assert_eq(invocation.app_package, default_package)
}

///|
async test "frontend build executes the host override from frontend.path" {
  let root = @async_fs.tmpdir(prefix="proton frontend build-")
  defer @async_fs.rmdir(root, recursive=true)
  let frontend = @fsutil.path_join(root, "frontend with spaces")
  let tools = @fsutil.path_join(root, "tools")
  @async_fs.mkdir(frontend)
  @async_fs.mkdir(tools)
  let helper = @fsutil.path_join(tools, "warren")
  @async_fs.write_file(
    helper,
    "#!/bin/sh\nprintf '%s' \"$1\" > result.txt\n",
    create_mode=CreateOrTruncate,
  )
  if @path.sep != '\\' {
    @async_fs.chmod(helper, 0o755)
  }
  @async_fs.write_file(
    @fsutil.path_join(tools, "warren.cmd"),
    "@echo off\r\necho %1> result.txt\r\n",
    create_mode=CreateOrTruncate,
  )
  let config_file = @fsutil.path_join(root, "proton.project.json")
  @async_fs.write_file(
    config_file,
    (
      #|{"identifier":"com.example.frontend","frontend":{"path":"missing","before_build":"exit 91","dist":"dist"},"platforms":{"macos":{"frontend":{"path":"frontend with spaces","before_build":"../tools/warren build"}},"linux":{"frontend":{"path":"frontend with spaces","before_build":"../tools/warren build"}},"windows":{"frontend":{"path":"frontend with spaces","before_build":"..\\tools\\warren.cmd build"}}}}
    ),
    create_mode=CreateOrTruncate,
  )
  let loaded = @project.load(config_file)
  run_frontend_build(loaded.base_dir, loaded.config)
  assert_eq(
    @async_fs.read_file(@fsutil.path_join(frontend, "result.txt"))
    .text()
    .trim()
    .to_owned(),
    "build",
  )
  assert_false(@fsutil.path_exists(@fsutil.path_join(root, "result.txt")))
}

///|
async test "build prepares the runtime before starting Moon" {
  let root = @async_fs.tmpdir(prefix="proton-auto-build-")
  defer @async_fs.rmdir(root, recursive=true)
  let store = @fsutil.path_join(root, "blocked-store")
  @async_fs.write_file(store, "not a directory", create_mode=CreateOrTruncate)
  let previous = @env.get_env_var("PROTON_RUNTIME_STORE")
  @env.set_env_var("PROTON_RUNTIME_STORE", store)
  defer (match previous {
    Some(value) => @env.set_env_var("PROTON_RUNTIME_STORE", value)
    None => @env.unset_env_var("PROTON_RUNTIME_STORE")
  })
  let source = @fsutil.path_join(root, "proton.project.json")
  @async_fs.write_file(
    source,
    "{\"identifier\":\"com.example.auto\"}",
    create_mode=CreateOrTruncate,
  )
  try run(root, command().parse(argv=[], env=Map([]))) catch {
    error => assert_true(error.to_string().contains(store))
  } noraise {
    _ => fail("installation failure must stop the build before Moon runs")
  }
}
