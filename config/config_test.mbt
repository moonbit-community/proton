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
test "parser decodes config string escapes" {
  let source =
    #|unicode = "caf\u{e9}"
    #|hex_octal = "A\x42\o101"
    #|controls = "\b\f\r\n\t"
    #|simple = "q:\" b:\\ a:\' t:\` f:\/ s:\ end"
    #|pair = "\uD83D\uDE00"
    #|lone_high = "\uD83D"
    #|lone_low = "\uDC00"
    #|too_big = "\u{110000}"
    #|pair_esc = "\u{1F600}"
    #|nul = "a\x00b"
    #|max_octal = "\o377"
    #|upper_hex = "\xAB"
    #|
  let (ast, reports) = parse_moon_proton(source)
  inspect(reports.length(), content="0")
  match ast {
    Obj(fields, _) => {
      let values : Array[String] = []
      for field in fields {
        match field.value {
          Str(text, _) => values.push(text)
          _ => fail("expected string value")
        }
      }
      assert_eq(values[0], "café")
      assert_eq(values[1], "ABA")
      assert_eq(values[2], "\b\f\r\n\t")
      assert_eq(values[3], "q:\" b:\\ a:' t:` f:/ s: end")
      assert_eq(values[4], "😀")
      assert_eq(values[5], "�")
      assert_eq(values[6], "�")
      assert_eq(values[7], "�")
      assert_eq(values[8], "😀")
      assert_eq(values[9], "a\u{0}b")
      assert_eq(values[10], "ÿ")
      assert_eq(values[11], "«")
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
test "project config requires an identifier for single instance mode" {
  let source =
    #|single_instance = true
    #|window = { title: "App", width: 900, height: 700 }
    #|entry = { kind: "html", value: "<main>App</main>" }
    #|
  let error = expect_project_config_error(() => {
    load_project_config_from_text(source, "target/proton-config")
  })
  assert_true(error.message().contains("identifier"))
  assert_true(error.message().contains("single_instance"))
}

///|
test "project config decodes single instance mode" {
  let source =
    #|identifier = "dev.proton.single-instance"
    #|single_instance = true
    #|window = { title: "App", width: 900, height: 700 }
    #|entry = { kind: "html", value: "<main>App</main>" }
    #|
  let config = load_project_config_from_text(source, "target/proton-config").config()
  assert_true(config.single_instance())
  assert_eq(config.metadata().identifier, Some("dev.proton.single-instance"))
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
    #|  sign: {
    #|    binaries: ["bin/worker"],
    #|  },
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
  let sign = bundle.sign.unwrap()
  assert_true(
    normalize_test_path(sign.binaries()[0]).has_suffix(
      "target/proton-config/subdir/bin/worker",
    ),
  )
  assert_true(
    normalize_test_path(bundle.output()).has_suffix(
      "target/proton-config/subdir/target/proton-dist",
    ),
  )
}

///|
fn project_config_for_path_test(entry : String, extra : String) -> String {
  "window = { title: \"App\", width: 900, height: 700 }\nentry = " +
  entry +
  "\n" +
  extra
}

///|
test "project config rejects absolute project paths with field-specific errors" {
  let html_entry = "{ kind: \"html\", value: \"<main>App</main>\" }"
  let cases = [
    (
      "entry.value",
      project_config_for_path_test(
        "{ kind: \"asset\", value: \"/frontend/index.html\" }", "",
      ),
    ),
    (
      "windows[0].entry.value",
      project_config_for_path_test(
        html_entry, "windows = [{ id: \"settings\", window: { title: \"Settings\", width: 600, height: 400 }, entry: { kind: \"file\", value: \"C:/app/settings.html\" } }]",
      ),
    ),
    (
      "backend.path",
      project_config_for_path_test(
        html_entry, "backend = { path: \"/backend\", package: \"app\" }",
      ),
    ),
    (
      "frontend.path",
      project_config_for_path_test(
        html_entry, "frontend = { path: \"C:/frontend\" }",
      ),
    ),
    (
      "frontend.dist",
      project_config_for_path_test(
        html_entry, "frontend = { path: \"frontend\", dist: \"/dist\" }",
      ),
    ),
    (
      "bundle.icon[0]",
      project_config_for_path_test(
        html_entry, "bundle = { icon: [\"/icons/app.icns\"] }",
      ),
    ),
    (
      "bundle.resources[0]",
      project_config_for_path_test(
        html_entry, "bundle = { resources: [\"C:/resources/**\"] }",
      ),
    ),
    (
      "bundle.sign.binaries[0]",
      project_config_for_path_test(
        html_entry, "bundle = { sign: { binaries: [\"/bin/worker\"] } }",
      ),
    ),
    (
      "bundle.output",
      project_config_for_path_test(
        html_entry, "bundle = { output: \"/target/proton-dist\" }",
      ),
    ),
  ]
  for _, item in cases {
    let (label, source) = item
    let error = expect_project_config_error(() => {
      load_project_config_from_text(source, "target/proton-config")
    })
    assert_eq(
      error.message(),
      "moon.proton." +
      label +
      " must be a relative path; absolute paths and drive prefixes are not allowed",
    )
  }
}

///|
test "project config rejects signing binary globs under the correct field" {
  let source = project_config_for_path_test(
    "{ kind: \"html\", value: \"<main>App</main>\" }", "bundle = { sign: { binaries: [\"bin/*.exe\"] } }",
  )
  let error = expect_project_config_error(() => {
    load_project_config_from_text(source, "target/proton-config")
  })
  assert_eq(
    error.message(),
    "moon.proton.bundle.sign.binaries[0] must name one file; glob patterns are not supported",
  )
}

///|
test "project config rejects backslashes in portable project paths" {
  let source =
    #|window = { title: "App", width: 900, height: 700 }
    #|entry = {
    #|  kind: "asset",
    #|  value: "frontend\\dist\\index.html",
    #|}
    #|
  let error = expect_project_config_error(() => {
    load_project_config_from_text(source, "target/proton-config")
  })
  assert_eq(
    error.message(),
    "moon.proton.entry.value must use '/' separators; backslashes are not allowed in portable project paths",
  )
}

///|
test "project config rebases portable paths into host path components" {
  let source =
    #|window = { title: "App", width: 900, height: 700 }
    #|entry = {
    #|  kind: "asset",
    #|  value: "frontend/dist/index.html",
    #|}
    #|
  let config = load_project_config_from_text(source, "target/proton-config").config()
  match config.entry() {
    Asset(path) => {
      let entry : @mbpath.Path = path
      assert_eq(entry.basename().to_owned(), "index.html")
      assert_eq(entry.dirname().basename().to_owned(), "dist")
    }
    _ => abort("expected asset entry")
  }
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
    #|permissions = []
    #|debug = true
    #|debug = false
    #|
  let error = expect_project_config_error(() => {
    load_project_config_from_text(source, "target/proton-config")
  })
  assert_eq(
    error.message(),
    "Unexpected key 'legacy_runtime' found in moon.proton.\nUnexpected key 'unknown_thing' found in moon.proton.\nDuplicate key 'debug' found in moon.proton.",
  )
}

///|
test "project config decodes scoped permission grants" {
  let source =
    #|window = { title: "Main", width: 900, height: 700 }
    #|entry = { kind: "asset", value: "app.html" }
    #|windows = [{
    #|  id: "settings",
    #|  open_on_start: false,
    #|  window: { title: "Settings", width: 480, height: 360 },
    #|  entry: { kind: "asset", value: "settings.html" },
    #|}]
    #|permissions = [
    #|  {
    #|    window: "main",
    #|    origin: "app",
    #|    extension: "justjavac/proton-fs",
    #|    scope: {
    #|      read: ["./data"],
    #|      write: false,
    #|    },
    #|  },
    #|  {
    #|    window: "settings",
    #|    origin: "entry",
    #|    extension: "justjavac/proton-dialog",
    #|  },
    #|]
    #|
  let config = load_project_config_from_text(source, ".").config()
  let grants = config.permissions()
  assert_eq(grants.length(), 2)
  assert_eq(grants[0].window, "main")
  assert_eq(grants[0].origin, "app")
  assert_eq(grants[0].extension, "justjavac/proton-fs")
  match grants[0].scope {
    Object(scope) => {
      @debug.assert_eq(
        scope.get("read"),
        Some(Json::array([Json::string("./data")])),
      )
      @debug.assert_eq(scope.get("write"), Some(Json::boolean(false)))
    }
    _ => abort("expected permission scope object")
  }
  @debug.assert_eq(grants[1].scope, Json::empty_object())
}

///|
test "project config rejects ambiguous permission grants" {
  let source =
    #|window = { title: "Main", width: 900, height: 700 }
    #|entry = { kind: "asset", value: "app.html" }
    #|permissions = [
    #|  { window: "main", origin: "app", extension: "fs" },
    #|  { window: "main", origin: "app", extension: "fs" },
    #|]
    #|
  let error = expect_project_config_error(() => {
    load_project_config_from_text(source, ".")
  })
  assert_eq(error.message(), "duplicate value in permissions: main/app/fs")
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
test "project config decodes secondary windows and macOS launch metadata" {
  let source =
    #|window = {
    #|  title: "Main",
    #|  width: 900,
    #|  height: 700,
    #|  size_hint: "fixed",
    #|}
    #|
    #|entry = {
    #|  kind: "html",
    #|  value: "<main>Main</main>",
    #|}
    #|
    #|windows = [{
    #|  id: "settings",
    #|  window: {
    #|    title: "Settings",
    #|    width: 480,
    #|    height: 360,
    #|  },
    #|  entry: {
    #|    kind: "file",
    #|    value: "settings.html",
    #|  },
    #|}]
    #|
    #|bundle = {
    #|  active: true,
    #|  url_schemes: ["devtoys"],
    #|  document_types: [{
    #|    name: "Text",
    #|    extensions: ["txt", "md"],
    #|    role: "Editor",
    #|  }],
    #|}
    #|
  let config = load_project_config_from_text(source, "target/proton-config").config()
  assert_eq(config.windows().length(), 1)
  assert_eq(config.windows()[0].id, "settings")
  assert_true(config.windows()[0].open_on_start)
  let entries = config.entries()
  assert_eq(entries.length(), 2)
  assert_eq(entries[0], ProjectEntry::Html("<main>Main</main>"))
  match entries[1] {
    ProjectEntry::File(path) =>
      assert_true(
        normalize_test_path(path).has_suffix(
          "target/proton-config/settings.html",
        ),
      )
    _ => abort("expected secondary file entry")
  }
  let bundle = config.bundle().unwrap()
  assert_eq(bundle.url_schemes, ["devtoys"])
  assert_eq(bundle.document_types.length(), 1)
  assert_eq(bundle.document_types[0].extensions, ["txt", "md"])
}

///|
test "project config rejects reserved window ids and invalid document extensions" {
  let reserved =
    #|window = { title: "Main", width: 900, height: 700 }
    #|entry = { kind: "html", value: "<main>Main</main>" }
    #|windows = [{
    #|  id: "main",
    #|  window: { title: "Other", width: 480, height: 360 },
    #|  entry: { kind: "html", value: "other" },
    #|}]
    #|
  let reserved_error = expect_project_config_error(() => {
    load_project_config_from_text(reserved, ".")
  })
  assert_true(
    reserved_error.message().contains("unsupported windows[0].id: main"),
  )
  let invalid_extension =
    #|window = { title: "Main", width: 900, height: 700 }
    #|entry = { kind: "html", value: "<main>Main</main>" }
    #|bundle = {
    #|  document_types: [{
    #|    name: "Text",
    #|    extensions: [".txt"],
    #|  }],
    #|}
    #|
  let extension_error = expect_project_config_error(() => {
    load_project_config_from_text(invalid_extension, ".")
  })
  assert_true(
    extension_error
    .message()
    .contains("unsupported bundle.document_types[0].extensions: .txt"),
  )
}

///|
fn normalize_test_path(path : String) -> String {
  path.replace(old="\\", new="/")
}

///|
test "decodes an updater block" {
  let text =
    #|window = { title: "App", width: 800, height: 600 }
    #|entry = { kind: "html", value: "<html></html>" }
    #|
    #|updater = {
    #|  endpoint: "https://example.com/latest.json",
    #|  public_keys: ["rsa-sha256:aa:010001"],
    #|}
  let config = load_project_config_from_text(text, ".", name="moon.proton").config()
  let updater = config.updater().unwrap()
  assert_true(updater.is_active())
  assert_eq(updater.endpoint(), "https://example.com/latest.json")
  assert_eq(updater.public_keys(), ["rsa-sha256:aa:010001"])
  // Checking on launch and a thirty day window are the documented defaults.
  assert_true(updater.checks_on_launch())
  assert_eq(updater.freshness_days(), 30)
}

///|
test "an absent updater block leaves the channel unconfigured" {
  let text =
    #|window = { title: "App", width: 800, height: 600 }
    #|entry = { kind: "html", value: "<html></html>" }
  let config = load_project_config_from_text(text, ".", name="moon.proton").config()
  assert_eq(config.updater(), None)
}

///|
test "rejects an active updater that cannot be trusted or reached" {
  let with_body = fn(body : String) {
    (
      $|window = { title: "App", width: 800, height: 600 }
      $|entry = { kind: "html", value: "<html></html>" }
      $|
      $|updater = {\{body}}
    )
  }
  let failure = fn(body : String) -> String {
    let _ = load_project_config_from_text(
      with_body(body),
      ".",
      name="moon.proton",
    ) catch {
      error => return error.message()
    }
    abort("expected \{body} to be rejected")
  }
  // An empty trusted list is a configuration error, not permission to skip
  // verification.
  assert_true(
    failure("endpoint: \"https://example.com/latest.json\", public_keys: []").contains(
      "public_keys",
    ),
  )
  assert_true(
    failure("public_keys: [\"rsa-sha256:aa:010001\"]").contains("endpoint"),
  )
  assert_true(
    failure(
      "endpoint: \"http://example.com/latest.json\", public_keys: [\"rsa-sha256:aa:010001\"]",
    ).contains("endpoint"),
  )
  assert_true(
    failure(
      "endpoint: \"https://example.com/latest.json\", public_keys: [\"rsa-sha256:aa:010001\"], freshness_days: 0",
    ).contains("freshness_days"),
  )
  assert_true(failure("unknown_field: true").contains("unknown_field"))
}

///|
test "an inactive updater needs no endpoint or keys" {
  let text =
    #|window = { title: "App", width: 800, height: 600 }
    #|entry = { kind: "html", value: "<html></html>" }
    #|
    #|updater = { active: false }
  let config = load_project_config_from_text(text, ".", name="moon.proton").config()
  let updater = config.updater().unwrap()
  assert_false(updater.is_active())
}
