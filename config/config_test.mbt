///|
fn[T] expect_project_config_error(
  action : () -> T raise ProjectConfigError,
) -> ProjectConfigError raise {
  try action() catch {
    error => error
  } noraise {
    _ => fail("expected project config operation to fail")
  }
}

///|
test "parse moon.proton minimal config" {
  let source =
    #|window = {
    #|  title: "App",
    #|  width: 900,
    #|  height: 700,
    #|}
    #|
    #|entry = {
    #|  kind: "file",
    #|  value: "app.html",
    #|}
    #|
  let (ast, reports) = parse_moon_proton(source)
  inspect(reports.length(), content="0")
  match ast {
    Obj(fields, _) => {
      inspect(fields.length(), content="2")
      inspect(fields[0].key, content="window")
      inspect(fields[1].key, content="entry")
    }
    _ => fail("expected object")
  }
}

///|
test "parse moon.ext package metadata" {
  let source =
    #|id = "justjavac/proton-fs"
    #|namespace = "fs"
    #|package = "@justjavac/proton-fs"
    #|platforms = ["windows", "macos", "linux"]
    #|
  let (ast, reports) = parse_moon_ext(source)
  inspect(reports.length(), content="0")
  match ast {
    Obj(fields, _) => inspect(fields.length(), content="4")
    _ => fail("expected object")
  }
}

///|
test "parser preserves duplicate fields for decoder" {
  let source =
    #|debug = true
    #|debug = false
    #|
  let (ast, reports) = parse_moon_proton(source)
  inspect(reports.length(), content="0")
  match ast {
    Obj(fields, _) => {
      inspect(fields.length(), content="2")
      inspect(fields[0].key, content="debug")
      inspect(fields[1].key, content="debug")
    }
    _ => fail("expected object")
  }
}

///|
test "parser requires separators inside arrays and objects" {
  let source =
    #|window = {
    #|  title: "App"
    #|  width: 900,
    #|  height: 700,
    #|}
    #|
    #|platforms = ["windows" "linux"]
    #|
  let (_ast, reports) = parse_moon_proton(source)
  inspect(reports.length(), content="2")
  inspect(reports[0].msg, content="expected `,` or `}` after object field")
  inspect(reports[1].msg, content="expected `,` or `]` after array item")
}

///|
test "project config rejects unsupported window size_hint" {
  let source =
    #|window = {
    #|  title: "App",
    #|  width: 900,
    #|  height: 700,
    #|  size_hint: "stretch",
    #|}
    #|
    #|entry = {
    #|  kind: "url",
    #|  value: "http://localhost:5173",
    #|}
    #|
  let error = expect_project_config_error(() => {
    load_project_config_from_text(source, "target/proton-config")
  })
  assert_true(error.message().contains("unsupported window.size_hint"))
}

///|
test "project config parses default titlebar style" {
  let source =
    #|window = {
    #|  title: "App",
    #|  width: 900,
    #|  height: 700,
    #|  titlebar_style: "default",
    #|}
    #|
    #|entry = {
    #|  kind: "url",
    #|  value: "http://localhost:5173",
    #|}
    #|
  let config = load_project_config_from_text(source, "target/proton-config").config()
  assert_true(config.window.titlebar_style == TitlebarDefault)
}

///|
test "project config parses overlay titlebar style" {
  let source =
    #|window = {
    #|  title: "App",
    #|  width: 900,
    #|  height: 700,
    #|  titlebar_style: "overlay",
    #|}
    #|
    #|entry = {
    #|  kind: "url",
    #|  value: "http://localhost:5173",
    #|}
    #|
  let config = load_project_config_from_text(source, "target/proton-config").config()
  assert_true(config.window.titlebar_style == TitlebarOverlay)
}

///|
test "project config rejects unsupported titlebar style" {
  let source =
    #|window = {
    #|  title: "App",
    #|  width: 900,
    #|  height: 700,
    #|  titlebar_style: "hiddenInset",
    #|}
    #|
    #|entry = {
    #|  kind: "url",
    #|  value: "http://localhost:5173",
    #|}
    #|
  let error = expect_project_config_error(() => {
    load_project_config_from_text(source, "target/proton-config")
  })
  assert_true(error.message().contains("unsupported window.titlebar_style"))
}

///|
test "project config rebases file entry and frontend paths from config directory" {
  let base_dir = "target/proton-config/subdir"
  let source =
    #|window = {
    #|  title: "App",
    #|  width: 900,
    #|  height: 700,
    #|}
    #|
    #|entry = {
    #|  kind: "asset",
    #|  value: "frontend/dist/index.html",
    #|}
    #|
    #|backend = {
    #|  path: "backend module",
    #|  package: "app",
    #|}
    #|
    #|frontend = {
    #|  dev_url: "http://localhost:5173",
    #|  dist: "dist",
    #|  path: "frontend module",
    #|}
    #|
    #|bundle = {
    #|  targets: ["app", "zip", "dmg"],
    #|  icon: ["icons/icon.ico"],
    #|  resources: ["resources/**"],
    #|  output: "target/proton-dist",
    #|}
    #|
  let config = load_project_config_from_text(source, base_dir).config()
  match config.entry() {
    Asset(path) =>
      assert_true(
        normalize_test_path(path).has_suffix(
          "target/proton-config/subdir/frontend/dist/index.html",
        ),
      )
    _ => abort("expected asset entry")
  }
  let backend = config.backend().unwrap()
  assert_eq(backend.app_package(), "app")
  assert_true(
    normalize_test_path(backend.path()).has_suffix(
      "target/proton-config/subdir/backend module",
    ),
  )
  let frontend = config.frontend().unwrap()
  assert_true(
    normalize_test_path(frontend.dist().unwrap()).has_suffix(
      "target/proton-config/subdir/frontend module/dist",
    ),
  )
  assert_true(
    normalize_test_path(frontend.path().unwrap()).has_suffix(
      "target/proton-config/subdir/frontend module",
    ),
  )
  let bundle = config.bundle().unwrap()
  assert_eq(bundle.targets, ["app", "zip", "dmg"])
  assert_true(
    normalize_test_path(bundle.icon[0]).has_suffix(
      "target/proton-config/subdir/icons/icon.ico",
    ),
  )
  assert_true(
    normalize_test_path(bundle.resources[0]).has_suffix(
      "target/proton-config/subdir/resources/**",
    ),
  )
  assert_true(
    normalize_test_path(bundle.output()).has_suffix(
      "target/proton-config/subdir/target/proton-dist",
    ),
  )
}

///|
test "project config reads module metadata from configured backend" {
  let project_dir = "target/project-config-backend-metadata"
  let backend_dir = project_dir + "/backend"
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.create_dir(project_dir) catch {
    _ => ()
  }
  @mbfs.create_dir(backend_dir) catch {
    _ => ()
  }
  @mbfs.write_string_to_file(
    backend_dir + "/moon.mod",
    (
      #|name = "example/backend"
      #|version = "1.2.3"
      #|description = "Backend module metadata"
      #|license = "Apache-2.0"
      #|
    ),
    encoding="utf8",
  ) catch {
    error => abort(@debug.render(Repr(error)))
  }
  let source =
    #|window = {
    #|  title: "App",
    #|  width: 900,
    #|  height: 700,
    #|}
    #|
    #|entry = {
    #|  kind: "asset",
    #|  value: "frontend/dist/index.html",
    #|}
    #|
    #|backend = {
    #|  path: "backend",
    #|  package: "app",
    #|}
    #|
  let metadata = load_project_config_from_text(source, project_dir)
    .config()
    .metadata()
  assert_eq(metadata.version, Some("1.2.3"))
  assert_eq(metadata.description, Some("Backend module metadata"))
  assert_eq(metadata.license, Some("Apache-2.0"))
}

///|
test "project config rejects legacy frontend cwd" {
  let source =
    #|window = {
    #|  title: "App",
    #|  width: 900,
    #|  height: 700,
    #|}
    #|
    #|entry = {
    #|  kind: "html",
    #|  value: "<main>App</main>",
    #|}
    #|
    #|frontend = {
    #|  cwd: "frontend",
    #|}
    #|
  let error = expect_project_config_error(() => {
    load_project_config_from_text(source, "target/proton-config")
  })
  assert_eq(
    error.message(),
    "Unexpected key 'cwd' found in moon.proton field `frontend`.",
  )
}

///|
test "project config aggregates unknown and duplicate top-level fields" {
  let source =
    #|window = {
    #|  title: "App",
    #|  width: 900,
    #|  height: 700,
    #|}
    #|
    #|entry = {
    #|  kind: "url",
    #|  value: "http://localhost:5173",
    #|}
    #|
    #|legacy_runtime = true
    #|unknown_thing = 1
    #|permissions = {}
    #|debug = true
    #|debug = false
    #|
  let error = expect_project_config_error(() => {
    load_project_config_from_text(source, "target/proton-config")
  })
  assert_eq(
    error.message(),
    "Unexpected key 'legacy_runtime' found in moon.proton.\nUnexpected key 'unknown_thing' found in moon.proton.\nmoon.proton field `permissions` is not supported in v1.\nDuplicate key 'debug' found in moon.proton.",
  )
}

///|
test "project config aggregates unknown and duplicate object fields" {
  let source =
    #|window = {
    #|  title: "App",
    #|  width: 900,
    #|  height: 700,
    #|  title: "Other",
    #|  extra: 1,
    #|}
    #|
    #|entry = {
    #|  kind: "url",
    #|  value: "http://localhost:5173",
    #|}
    #|
  let error = expect_project_config_error(() => {
    load_project_config_from_text(source, "target/proton-config")
  })
  assert_eq(
    error.message(),
    "Duplicate key 'title' found in moon.proton field `window`.\nUnexpected key 'extra' found in moon.proton field `window`.",
  )
}

///|
test "project config load reports no warnings by default" {
  let source =
    #|window = {
    #|  title: "App",
    #|  width: 900,
    #|  height: 700,
    #|}
    #|
    #|entry = {
    #|  kind: "url",
    #|  value: "http://localhost:5173",
    #|}
    #|
  let loaded = load_project_config_from_text(source, "target/proton-config")
  assert_eq(loaded.warnings(), [])
}

///|
test "loaded project config carries warnings" {
  let source =
    #|window = {
    #|  title: "App",
    #|  width: 900,
    #|  height: 700,
    #|}
    #|
    #|entry = {
    #|  kind: "url",
    #|  value: "http://localhost:5173",
    #|}
    #|
  let loaded = load_project_config_from_text(source, "target/proton-config")
  let with_warnings = LoadedProjectConfig::new(loaded.config(), warnings=[
    "moon.proton field `legacy` is deprecated",
  ])
  assert_eq(with_warnings.warnings(), [
    "moon.proton field `legacy` is deprecated",
  ])
  assert_eq(with_warnings.config(), loaded.config())
}

///|
fn normalize_test_path(path : String) -> String {
  path.replace(old="\\", new="/")
}
