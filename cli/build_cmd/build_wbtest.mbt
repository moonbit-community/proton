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
async fn[T] expect_build_config_error(
  action : async () -> T raise BuildConfigError,
) -> BuildConfigError {
  try action() catch {
    error => error
  } noraise {
    _ => fail("expected build config error")
  }
}

///|
fn ensure_build_test_dir(path : String) -> Unit {
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir(path) catch {
    _ => ()
  }
}

///|
fn write_build_test_file(path : String, text : String) -> Unit {
  @mbfs.write_string_to_file(path, text, encoding="utf8") catch {
    err => abort(@debug.render(Repr(err)))
  }
}

///|
let valid_build_config =
  #|window = {
  #|  title: "Build Test",
  #|  width: 320,
  #|  height: 240,
  #|}
  #|
  #|entry = {
  #|  kind: "asset",
  #|  value: "frontend/dist/index.html",
  #|}
  #|

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
    "--package", "desktop", "--config", "config/moon.proton", "--no-frontend",
  ])
  @debug.assert_eq(raw.app_package, Some("desktop"))
  @debug.assert_eq(raw.config_path, Some("config/moon.proton"))
  @debug.assert_eq(raw.run_frontend_build, false)
}

///|
test "parse build args accepts an isolated Moon target directory" {
  let raw = parse_build_args([
    "--package", "app", "--moon-target-dir", "target/build-app",
  ])
  @debug.assert_eq(raw.moon_target_dir, Some("target/build-app"))
}

///|
test "parse build args accepts explicit config path starting with dash" {
  let raw = parse_build_args(["--config", "-custom.proton"])
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
      Some("target/build-app"),
    ),
    [
      "--target-dir", "target/build-app", "build", "app", "--diagnostic-limit", "80",
      "--target", "native",
    ],
  )
}

///|
async test "frontend path validation reports missing directory" {
  let root = "target/proton-build-cwd"
  ensure_build_test_dir(root)
  let error = try
    resolve_frontend_path(root, Some("missing"), "npm run build")
  catch {
    BuildPathError::Missing(..) as error => error.message()
    error => fail("unexpected error: " + @debug.render(Repr(error)))
  } noraise {
    _ => fail("expected build error")
  }
  assert_true(error.contains("frontend path does not exist"))
}

///|
async test "backend path supports nested directories with spaces" {
  let root = "target/proton build backend"
  ensure_build_test_dir(root)
  ensure_build_test_dir(join_path(root, "nested"))
  ensure_build_test_dir(join_path(root, "nested/backend app"))
  let path = resolve_backend_path(root, Some("nested/backend app"))
  @debug.assert_eq(path, resolve_path(root, "nested/backend app"))
}

///|
async test "build config discovery prefers package-local moon.proton" {
  let root = "target/proton-build-package-config"
  ensure_build_test_dir(root)
  ensure_build_test_dir(join_path(root, "desktop"))
  let package_config = join_path(join_path(root, "desktop"), "moon.proton")
  write_build_test_file(package_config, "")
  let raw = parse_build_args(["--package", "desktop"])
  let resolved = resolve_build_config_path(root, root, raw)
  @debug.assert_eq(resolved, Some(resolve_path(root, "desktop/moon.proton")))
}

///|
async test "resolve path accepts Windows backslash relative input" {
  if @path.sep == '\\' {
    let dir = "target/proton-build-path"
    ensure_build_test_dir(dir)
    let resolved = resolve_path(".", "target\\proton-build-path")
    assert_true(resolved.contains(":/") || resolved.contains(":\\"))
    assert_true(path_exists(resolved))
    let absolute = resolved.replace_all(old="/", new="\\")
    assert_true(path_exists(resolve_path(".", absolute)))
  }
}

///|
async test "project config validation rejects unknown top-level fields" {
  let dir = "target/proton-build-config"
  ensure_build_test_dir(dir)
  let path = join_path(dir, "unknown.moon.proton")
  write_build_test_file(path, valid_build_config + "\nlegacy_runtime = true\n")
  let error = expect_build_config_error(() => read_project_config(path))
  assert_eq(
    error,
    BuildConfigError::Invalid(
      path~,
      error=@proton_config.ProjectConfigError::UnknownField(
        path="moon.proton.legacy_runtime",
      ),
    ),
  )
}

///|
async test "project config validation requires window" {
  let dir = "target/proton-build-config"
  ensure_build_test_dir(dir)
  let path = join_path(dir, "missing-window.moon.proton")
  write_build_test_file(
    path,
    (
      #|entry = {
      #|  kind: "asset",
      #|  value: "frontend/dist/index.html",
      #|}
      #|
    ),
  )
  let error = expect_build_config_error(() => read_project_config(path))
  assert_eq(
    error,
    BuildConfigError::Invalid(
      path~,
      error=@proton_config.ProjectConfigError::MissingField(
        path="moon.proton.window",
      ),
    ),
  )
}

///|
async test "project config validation rejects unsupported size_hint" {
  let dir = "target/proton-build-config"
  ensure_build_test_dir(dir)
  let path = join_path(dir, "bad-size-hint.moon.proton")
  write_build_test_file(
    path,
    (
      #|window = {
      #|  title: "Build Test",
      #|  width: 320,
      #|  height: 240,
      #|  size_hint: "stretch",
      #|}
      #|
      #|entry = {
      #|  kind: "asset",
      #|  value: "frontend/dist/index.html",
      #|}
      #|
    ),
  )
  let error = expect_build_config_error(() => read_project_config(path))
  assert_eq(
    error,
    BuildConfigError::Invalid(
      path~,
      error=@proton_config.ProjectConfigError::UnsupportedValue(
        path="window.size_hint",
        value="stretch",
      ),
    ),
  )
}

///|
async test "project config parsing keeps active bundle metadata out of build validation" {
  let dir = "target/proton-build-config"
  ensure_build_test_dir(dir)
  let path = join_path(dir, "active-bundle.moon.proton")
  write_build_test_file(
    path,
    valid_build_config +
    (
      #|
      #|bundle = {
      #|  active: true,
      #|}
      #|
    ),
  )
  ignore(read_project_config(path))
}

///|
async test "production entry validation requires file-backed entry" {
  let error = try
    validate_production_entry_file(
      @proton_config.ProjectEntry::Asset("target/proton-build-missing.html"),
    )
  catch {
    BuildPathError::Missing(..) as error => error.message()
    error => fail("unexpected error: " + @debug.render(Repr(error)))
  } noraise {
    _ => fail("expected build error")
  }
  assert_true(error.contains("production entry does not exist"))
  let dir = "target/proton-build-entry"
  ensure_build_test_dir(dir)
  let file = join_path(dir, "index.html")
  @mbfs.write_string_to_file(file, "<!doctype html>", encoding="utf8") catch {
    err => abort(@debug.render(Repr(err)))
  }
  validate_production_entry_file(@proton_config.ProjectEntry::Asset(file))
}

///|
test "frontend release rejects url production entry" {
  let frontend = Some(
    @proton_config.ProjectFrontendConfig::new(
      dist=Some("target/proton-build-entry"),
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
    entry: @proton_config.ProjectEntry::Url("http://localhost:5173"),
    backend: None,
    frontend: Some(
      @proton_config.ProjectFrontendConfig::new(
        dist=Some("target/proton-build-entry"),
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
    entry: @proton_config.ProjectEntry::Asset(
      "target/proton-build-entry/index.html",
    ),
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

///|
async test "production entry validation rejects directories" {
  let dir = "target/proton-build-entry-dir"
  ensure_build_test_dir(dir)
  let error = try
    validate_production_entry_file(@proton_config.ProjectEntry::Asset(dir))
  catch {
    BuildPathError::WrongKind(..) as error => error.message()
    error => fail("unexpected error: " + @debug.render(Repr(error)))
  } noraise {
    _ => fail("expected build error")
  }
  assert_true(error.contains("production entry is not a file"))
}
