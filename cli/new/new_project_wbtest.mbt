///|
fn must_parse(args : Array[String]) -> RawNewProjectOptions {
  new_options_from_matches(command().parse(argv=args, env=Map([]))) catch {
    err => abort(err.to_string())
  }
}

///|
fn must_options(
  args : Array[String],
) -> NewProjectOptions raise NewProjectInputError {
  options_from_raw(".", must_parse(args))
}

///|
fn must_plan(
  options : NewProjectOptions,
) -> Array[PlannedFile] raise NewProjectTemplateError {
  plan_project_files(
    options.title,
    options.author,
    options.project_name,
    options.identifier,
    options.width,
    options.height,
  )
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
  assert_eq(options.target_dir, "todo")
  assert_eq(options.title, "Todo")
  assert_eq(options.author, "username")
  assert_eq(options.project_name, "todo")
  assert_eq(options.identifier, "dev.proton.todo")
  assert_eq(options.width, 960)
  assert_eq(options.height, 640)
  assert_true(options.run_check)
  assert_false(options.yes)
  assert_false(options.dry_run)
}

///|
test "path slug drives default title and module names" {
  let options = must_options(["tools/my-counter"])
  assert_eq(options.target_dir, "tools/my-counter")
  assert_eq(options.title, "My Counter")
  assert_eq(options.author, "username")
  assert_eq(options.project_name, "my-counter")
  assert_eq(options.identifier, "dev.proton.my-counter")
}

///|
test "current directory path uses cwd basename as default slug" {
  let options = options_from_raw(
    "C:\\Users\\dev\\sample-app",
    must_parse(["."]),
  )
  assert_eq(options.target_dir, ".")
  assert_eq(options.title, "Sample App")
  assert_eq(options.author, "username")
  assert_eq(options.project_name, "sample-app")
  assert_eq(options.identifier, "dev.proton.sample-app")
}

///|
test "parent directory slug derives from cwd" {
  assert_eq(project_slug("C:\\Users\\dev\\sample-app", ".."), "dev")
  assert_eq(project_slug("plaindir", ".."), "plaindir")
}

///|
test "explicit title author size and flags override defaults" {
  let options = must_options([
    "demo", "--title", "Demo App", "--author", "moonbit-community", "--identifier",
    "com.justjavac.demo", "--width", "1024", "--height", "720", "--no-check", "--dry-run",
    "-y",
  ])
  assert_eq(options.title, "Demo App")
  assert_eq(options.author, "moonbit-community")
  assert_eq(options.project_name, "demo")
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
  try options_from_raw(".", must_parse(["demo", "--width", "0"])) catch {
    NewProjectInputError::InvalidPositiveInteger(field="width", value="0") => ()
    _ => abort("expected invalid width")
  } noraise {
    _ => abort("expected width to fail")
  }
  try options_from_raw(".", must_parse(["demo", "--height", "abc"])) catch {
    NewProjectInputError::InvalidPositiveInteger(field="height", value="abc") =>
      ()
    _ => abort("expected invalid height")
  } noraise {
    _ => abort("expected height to fail")
  }
}

///|
test "invalid derived module names fail" {
  try
    options_from_raw(".", must_parse(["demo", "--author", "bad name"]))
  catch {
    NewProjectInputError::InvalidAuthor(
      author="bad name",
      reason="contains unsupported characters"
    ) => ()
    _ => abort("expected author with spaces to fail")
  } noraise {
    _ => abort("expected module to fail")
  }
  try
    options_from_raw(".", must_parse(["demo", "--author", "bad\"name"]))
  catch {
    NewProjectInputError::InvalidAuthor(
      author="bad\"name",
      reason="contains unsupported characters"
    ) => ()
    _ => abort("expected unsupported author character")
  } noraise {
    _ => abort("expected module to fail")
  }
  try
    options_from_raw(".", must_parse(["demo", "--author", "nested/author"]))
  catch {
    NewProjectInputError::InvalidAuthor(
      author="nested/author",
      reason="must be one module path component"
    ) => ()
    _ => abort("expected nested author to fail")
  } noraise {
    _ => abort("expected author to fail")
  }
}

///|
test "default identifier normalizes common slug separators" {
  assert_eq(must_options(["my_app.demo"]).identifier, "dev.proton.my-app-demo")
}

///|
test "invalid identifier fails" {
  try
    options_from_raw(".", must_parse(["demo", "--identifier", "demo"]))
  catch {
    NewProjectInputError::InvalidBundleIdentifier(
      identifier="demo",
      reason="expected a reverse-DNS name"
    ) => ()
    _ => abort("expected reverse-DNS identifier error")
  } noraise {
    _ => abort("expected identifier to fail")
  }
  try
    options_from_raw(
      ".",
      must_parse(["demo", "--identifier", "com.example.bad_value"]),
    )
  catch {
    NewProjectInputError::InvalidBundleIdentifier(
      identifier="com.example.bad_value",
      reason="contains an unsupported character"
    ) => ()
    _ => abort("expected unsupported identifier character")
  } noraise {
    _ => abort("expected identifier character to fail")
  }
}

///|
test "file plan contains the exact isomorphic scaffold" {
  let files = must_plan(must_options(["my-counter"]))
  assert_eq(files.length(), 19)
  for
    path in [
      "AGENTS.md", "README.md", ".gitignore", "moon.work", "proton.project.json",
      "shared/moon.mod", "shared/moon.pkg", "shared/todo_contract.mbt", "frontend/moon.mod",
      "frontend/main/moon.pkg", "frontend/main/main.mbt", "frontend/public/index.html",
      "frontend/public/styles.css", "backend/moon.mod", "backend/app/moon.pkg", "backend/app/main.mbt",
      "backend/todo/moon.pkg", "backend/todo/backend.mbt", "backend/todo/commands.mbt",
    ] {
    guard find_planned_file(files, path) is Some(_) else {
      abort("missing planned file: " + path)
    }
  }
}

///|
test "templates receive final author title and size" {
  let files = must_plan(
    must_options([
      "demo", "--title", "Demo App", "--author", "moonbit-community", "--identifier",
      "com.justjavac.demo", "--width", "1000", "--height", "700",
    ]),
  )
  guard find_planned_file(files, "shared/moon.mod") is Some(shared_mod) else {
    abort("missing shared/moon.mod")
  }
  assert_true(shared_mod.contains("name = \"moonbit-community/demo_shared\""))
  assert_true(
    shared_mod.contains(
      "\"moonbit-community/proton_contract@" +
      default_proton_contract_version +
      "\"",
    ),
  )
  assert_false(shared_mod.contains("supported_targets"))
  guard find_planned_file(files, "shared/moon.pkg") is Some(shared_pkg) else {
    abort("missing shared/moon.pkg")
  }
  assert_false(shared_pkg.contains("supported_targets"))
  guard find_planned_file(files, "frontend/moon.mod") is Some(frontend_mod) else {
    abort("missing frontend/moon.mod")
  }
  assert_true(
    frontend_mod.contains("name = \"moonbit-community/demo_frontend\""),
  )
  assert_true(frontend_mod.contains("\"moonbit-community/demo_shared@0.1.0\""))
  assert_true(
    frontend_mod.contains(
      "\"moonbit-community/proton_client@" +
      default_proton_client_version +
      "\"",
    ),
  )
  assert_true(
    frontend_mod.contains(
      "\"moonbit-community/proton_rabbita@" +
      default_proton_rabbita_version +
      "\"",
    ),
  )
  guard find_planned_file(files, "backend/moon.mod") is Some(backend_mod) else {
    abort("missing backend/moon.mod")
  }
  assert_true(backend_mod.contains("name = \"moonbit-community/demo_backend\""))
  assert_true(
    backend_mod.contains(
      "\"moonbit-community/proton@" + default_proton_version + "\"",
    ),
  )
  assert_true(
    backend_mod.contains(
      "\"moonbit-community/proton_contract@" +
      default_proton_contract_version +
      "\"",
    ),
  )
  assert_false(backend_mod.contains("bin-deps"))
  assert_true(
    backend_mod.contains(
      "moonx moonbit-community/proton_codegen@" + default_proton_codegen_version,
    ),
  )
  guard find_planned_file(files, "backend/todo/moon.pkg") is Some(todo_pkg) else {
    abort("missing backend/todo/moon.pkg")
  }
  assert_true(todo_pkg.contains("rule: \"proton_codegen\""))
  assert_true(todo_pkg.contains("input: \"commands.mbt\""))
  assert_true(todo_pkg.contains("output: \"commands.g.mbt\""))
  guard find_planned_file(files, "backend/app/main.mbt") is Some(main_mbt) else {
    abort("missing backend/app/main.mbt")
  }
  assert_true(main_mbt.contains("@proton.asset("))
  assert_true(main_mbt.contains(".single_instance(\"com.justjavac.demo\")"))
  assert_true(main_mbt.contains("backend.register_commands(registrar)"))
  assert_false(main_mbt.contains(".permission("))
  guard find_planned_file(files, "proton.project.json") is Some(config) else {
    abort("missing proton.project.json")
  }
  let config_json = @json.parse(config) catch {
    error => abort(error.to_string())
  }
  guard config_json
    is {
      "backend": { "path": ".", "package": "backend/app", .. },
      "frontend": {
        "path": "frontend",
        "before_dev": before_dev,
        "before_build": before_build,
        ..
      },
      "package": {
        "product_name": "Demo App",
        "identifier": "com.justjavac.demo",
        "version": "0.1.0",
        "formats": ["app", "zip"],
        "output": "dist",
        ..
      },
      ..
    } else {
    abort("unexpected generated proton.project.json")
  }
  assert_eq(
    before_dev,
    ToJson::to_json(
      "moonx --target native moonbit-community/warren@" +
      default_warren_version +
      " dev --direct --port 4300",
    ),
  )
  assert_eq(
    before_build,
    ToJson::to_json(
      "moonx --target native moonbit-community/warren@" +
      default_warren_version +
      " build",
    ),
  )
  guard find_planned_file(files, "README.md") is Some(readme) else {
    abort("missing README.md")
  }
  guard find_planned_file(files, "frontend/public/index.html") is Some(app_html) else {
    abort("missing frontend/public/index.html")
  }
  assert_true(app_html.contains("<title>Demo App</title>"))
  assert_true(app_html.contains("href=\"./styles.css\""))
  assert_false(app_html.contains("href=\"/styles.css\""))
  assert_true(readme.contains("## Dev"))
  assert_false(readme.contains("moon install moonbit-community/warren"))
  assert_true(
    readme.contains("Warren " + default_warren_version + " through `moonx`"),
  )
  assert_true(readme.contains("proton_cli dev"))
  assert_true(readme.contains("## Build"))
  assert_true(readme.contains("proton_cli build"))
  assert_true(readme.contains("## Package"))
  assert_true(readme.contains("shared/"))
  assert_true(readme.contains("proton_cli package --dry-run"))
}

///|
test "user title can contain template braces" {
  let files = must_plan(
    must_options(["demo", "--title", "A {{ Demo }}", "--author", "braces"]),
  )
  guard find_planned_file(files, "proton.project.json") is Some(config) else {
    abort("missing proton.project.json")
  }
  let config_json = @json.parse(config) catch {
    error => abort(error.to_string())
  }
  guard config_json is { "package": { "product_name": "A {{ Demo }}", .. }, .. } else {
    abort("generated title did not preserve template braces")
  }
}

///|
test "template render error names template" {
  let context = template_context(
    "Demo", "username", "demo", "dev.proton.demo", 960, 640,
  )
  try
    render_template(
      {
        output_path: "broken",
        template_name: "broken.tmpl",
        template_source: "{{missing}}",
      },
      context,
    )
  catch {
    NewProjectTemplateError::UnresolvedPlaceholder(template="broken.tmpl") => ()
    _ => abort("expected broken template name")
  } noraise {
    _ => abort("expected render error")
  }
}
