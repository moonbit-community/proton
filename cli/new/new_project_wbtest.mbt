///|
fn must_parse(args : Array[String]) -> RawNewProjectOptions {
  parse_new_args(args) catch {
    err => abort(err.to_string())
  }
}

///|
fn must_options(args : Array[String]) -> NewProjectOptions {
  match options_from_raw(".", must_parse(args)) {
    Ok(options) => options
    Err(message) => abort(message)
  }
}

///|
fn must_plan(options : NewProjectOptions) -> Array[PlannedFile] {
  match
    plan_project_files(
      options.title,
      options.module_name,
      options.identifier,
      options.width,
      options.height,
    ) {
    Ok(files) => files
    Err(message) => abort(message)
  }
}

///|
fn find_planned_file(files : Array[PlannedFile], path : String) -> String? {
  for file in files {
    if file.path == path {
      return Some(file.content)
    }
  }
  None
}

///|
test "default new options" {
  let options = must_options([])
  assert_eq(options.target_dir, "counter")
  assert_eq(options.title, "Counter")
  assert_eq(options.module_name, "counter")
  assert_eq(options.identifier, "dev.proton.counter")
  assert_eq(options.width, 960)
  assert_eq(options.height, 640)
  assert_true(options.run_check)
  assert_false(options.yes)
  assert_false(options.dry_run)
}

///|
test "path slug drives default title and module" {
  let options = must_options(["tools/my-counter"])
  assert_eq(options.target_dir, "tools/my-counter")
  assert_eq(options.title, "My Counter")
  assert_eq(options.module_name, "my-counter")
  assert_eq(options.identifier, "dev.proton.my-counter")
}

///|
test "current directory path uses cwd basename as default slug" {
  let options = match
    options_from_raw("C:\\Users\\dev\\sample-app", must_parse(["."])) {
    Ok(options) => options
    Err(message) => abort(message)
  }
  assert_eq(options.target_dir, ".")
  assert_eq(options.title, "Sample App")
  assert_eq(options.module_name, "sample-app")
  assert_eq(options.identifier, "dev.proton.sample-app")
}

///|
test "explicit title module size and flags override defaults" {
  let options = must_options([
    "demo", "--title", "Demo App", "--module", "justjavac/demo", "--identifier",
    "com.justjavac.demo", "--width", "1024", "--height", "720", "--no-check", "--dry-run",
    "-y",
  ])
  assert_eq(options.title, "Demo App")
  assert_eq(options.module_name, "justjavac/demo")
  assert_eq(options.identifier, "com.justjavac.demo")
  assert_eq(options.width, 1024)
  assert_eq(options.height, 720)
  assert_false(options.run_check)
  assert_true(options.dry_run)
  assert_true(options.yes)
}

///|
test "git flag is tri-state" {
  assert_true(must_options(["demo"]).git is None)
  assert_true(must_options(["demo", "--git"]).git is Some(true))
  assert_true(must_options(["demo", "--no-git"]).git is Some(false))
}

///|
test "invalid dimensions fail" {
  match options_from_raw(".", must_parse(["demo", "--width", "0"])) {
    Ok(_) => abort("expected width to fail")
    Err(message) =>
      assert_true(message.contains("width must be a positive integer"))
  }
  match options_from_raw(".", must_parse(["demo", "--height", "abc"])) {
    Ok(_) => abort("expected height to fail")
    Err(message) =>
      assert_true(message.contains("height must be a positive integer"))
  }
}

///|
test "invalid module fails" {
  match options_from_raw(".", must_parse(["demo", "--module", "bad name"])) {
    Ok(_) => abort("expected module to fail")
    Err(message) =>
      assert_true(message.contains("module name must not contain spaces"))
  }
  match options_from_raw(".", must_parse(["demo", "--module", "bad\"name"])) {
    Ok(_) => abort("expected module to fail")
    Err(message) =>
      assert_true(
        message.contains("module name contains unsupported character"),
      )
  }
}

///|
test "default identifier normalizes common slug separators" {
  assert_eq(must_options(["my_app.demo"]).identifier, "dev.proton.my-app-demo")
}

///|
test "invalid identifier fails" {
  match options_from_raw(".", must_parse(["demo", "--identifier", "demo"])) {
    Ok(_) => abort("expected identifier to fail")
    Err(message) =>
      assert_true(message.contains("reverse-DNS bundle identifier"))
  }
  match
    options_from_raw(
      ".",
      must_parse(["demo", "--identifier", "com.example.bad_value"]),
    ) {
    Ok(_) => abort("expected identifier character to fail")
    Err(message) => assert_true(message.contains("unsupported character"))
  }
}

///|
test "file plan contains expected scaffold paths" {
  let files = must_plan(must_options(["my-counter"]))
  for
    path in [
      "AGENTS.md", "LICENSE", "README.mbt.md", ".gitignore", "moon.mod", "moon.proton",
      "app/moon.pkg", "app/main.mbt", "app/app.html", "extensions/counter/moon.pkg",
      "extensions/counter/counter.mbt", "extensions/counter/README.mbt.md",
    ] {
    guard find_planned_file(files, path) is Some(_) else {
      abort("missing planned file: " + path)
    }
  }
}

///|
test "templates receive final module title and size" {
  let files = must_plan(
    must_options([
      "demo", "--title", "Demo App", "--module", "justjavac/demo", "--identifier",
      "com.justjavac.demo", "--width", "1000", "--height", "700",
    ]),
  )
  guard find_planned_file(files, "app/moon.pkg") is Some(app_pkg) else {
    abort("missing app/moon.pkg")
  }
  assert_true(
    app_pkg.contains("\"justjavac/demo/extensions/counter\" @counter"),
  )
  guard find_planned_file(files, "app/main.mbt") is Some(main_mbt) else {
    abort("missing app/main.mbt")
  }
  assert_true(main_mbt.contains("@proton.config(\"moon.proton\")"))
  guard find_planned_file(files, "moon.proton") is Some(config) else {
    abort("missing moon.proton")
  }
  assert_true(config.contains("product_name = \"Demo App\""))
  assert_true(config.contains("identifier = \"com.justjavac.demo\""))
  assert_true(config.contains("title: \"Demo App\""))
  assert_true(config.contains("width: 1000"))
  assert_true(config.contains("height: 700"))
  assert_true(config.contains("bundle = {"))
  assert_true(config.contains("active: true"))
  assert_true(config.contains("targets: [\"app\", \"zip\"]"))
  assert_true(config.contains("output: \"target/proton-dist\""))
  guard find_planned_file(files, "README.mbt.md") is Some(readme) else {
    abort("missing README.mbt.md")
  }
  guard find_planned_file(files, "app/app.html") is Some(app_html) else {
    abort("missing app/app.html")
  }
  assert_false(app_html.contains("window.__MoonBit__.ready"))
  assert_true(app_html.contains("window.__MoonBit__.core.invokeOp"))
  assert_false(app_html.contains("waitForBridge"))
  assert_true(readme.contains("## Dev"))
  assert_true(readme.contains("proton_cli dev"))
  assert_true(readme.contains("## Build"))
  assert_true(readme.contains("proton_cli build"))
  assert_true(readme.contains("## Bundle"))
  assert_true(readme.contains("bundle = {"))
  assert_true(readme.contains("proton_cli package app --dry-run"))
}

///|
test "user title can contain template braces" {
  let files = must_plan(
    must_options(["demo", "--title", "A {{ Demo }}", "--module", "braces_demo"]),
  )
  guard find_planned_file(files, "moon.proton") is Some(config) else {
    abort("missing moon.proton")
  }
  assert_true(config.contains("product_name = \"A {{ Demo }}\""))
}

///|
test "template render error names template" {
  let context = template_context("Demo", "demo", "dev.proton.demo", 960, 640)
  let result = render_template(
    {
      output_path: "broken",
      template_name: "broken.tmpl",
      template_source: "{{missing}}",
    },
    context,
  )
  match result {
    Ok(_) => abort("expected render error")
    Err(message) => assert_true(message.contains("broken.tmpl"))
  }
}
