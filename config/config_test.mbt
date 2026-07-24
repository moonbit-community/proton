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
  let config = load_project_config_from_text(source, "target/proton-config")
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
  let config = load_project_config_from_text(source, "target/proton-config")
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
    #|frontend = {
    #|  dev_url: "http://localhost:5173",
    #|  dist: "frontend/dist",
    #|  cwd: "frontend",
    #|}
    #|
    #|bundle = {
    #|  icon: ["icons/icon.ico"],
    #|  resources: ["resources/**"],
    #|  output: "target/proton-dist",
    #|}
    #|
  let config = load_project_config_from_text(source, base_dir)
  match config.entry() {
    Asset(path) =>
      assert_true(
        normalize_test_path(path).has_suffix(
          "target/proton-config/subdir/frontend/dist/index.html",
        ),
      )
    _ => abort("expected asset entry")
  }
  let frontend = config.frontend().unwrap()
  assert_true(
    normalize_test_path(frontend.dist().unwrap()).has_suffix(
      "target/proton-config/subdir/frontend/dist",
    ),
  )
  assert_true(
    normalize_test_path(frontend.cwd().unwrap()).has_suffix(
      "target/proton-config/subdir/frontend",
    ),
  )
  let bundle = config.bundle().unwrap()
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
fn normalize_test_path(path : String) -> String {
  path.replace(old="\\", new="/")
}
