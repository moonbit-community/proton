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
test "frontend release rejects url production entry" {
  let frontend = Some(
    @proton_config.ProjectFrontendConfig::new(
      dist=Some("fixtures/frontend-dist"),
    ),
  )
  let error = expect_build_error_message(() => {
    validate_production_entry_kind(
      @proton_config.ProjectEntry::Url("http://localhost:5173"),
      frontend,
    )
  })
  assert_true(error.contains("frontend production entry"))
}

///|
test "frontend release config preflight rejects url entry" {
  let config = BuildProjectConfig::{
    base_dir: ".",
    entries: [@proton_config.ProjectEntry::Url("http://localhost:5173")],
    backend: None,
    frontend: Some(
      @proton_config.ProjectFrontendConfig::new(
        dist=Some("fixtures/frontend-dist"),
      ),
    ),
  }
  let error = expect_build_error_message(() => validate_release_config(config))
  assert_true(error.contains("frontend production entry"))
}

///|
test "frontend release requires dist" {
  let config = BuildProjectConfig::{
    base_dir: ".",
    entries: [
      @proton_config.ProjectEntry::Asset("fixtures/frontend-dist/index.html"),
    ],
    backend: None,
    frontend: Some(
      @proton_config.ProjectFrontendConfig::new(
        before_build=Some("npm run build"),
      ),
    ),
  }
  let error = expect_build_error_message(() => validate_release_config(config))
  assert_true(error.contains("frontend.dist is required"))
}
