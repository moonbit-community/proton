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
async fn remove_new_test_tree(path : String) -> Unit {
  if !@fsutil.path_exists(path) {
    return
  }
  if @fsutil.path_is_dir(path) {
    @async_fs.rmdir(path, recursive=true)
  } else {
    @async_fs.remove(path)
  }
}

///|
fn transaction_test_options(
  path : String,
) -> NewProjectOptions raise NewProjectInputError {
  must_options([path, "--no-check", "--no-git"])
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
  assert_eq(files.length(), 20)
  for
    path in [
      "AGENTS.md", "README.md", ".gitignore", "moon.work", "moon.proton", "shared/moon.mod",
      "shared/moon.pkg", "shared/todo_contract.mbt", "frontend/moon.mod", "frontend/main/moon.pkg",
      "frontend/main/main.mbt", "frontend/public/index.html", "frontend/public/styles.css",
      "backend/moon.mod", "backend/app/moon.pkg", "backend/app/main.mbt", "backend/todo/moon.pkg",
      "backend/todo/backend.mbt", "backend/todo/commands.mbt", "backend/todo/commands.g.mbt",
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
  guard find_planned_file(files, "backend/todo/commands.g.mbt")
    is Some(commands_g) else {
    abort("missing backend/todo/commands.g.mbt")
  }
  assert_true(commands_g.contains("register_commands"))
  guard find_planned_file(files, "backend/app/main.mbt") is Some(main_mbt) else {
    abort("missing backend/app/main.mbt")
  }
  assert_true(main_mbt.contains("@proton.config(\"moon.proton\")"))
  assert_true(main_mbt.contains("backend.register_commands(registrar)"))
  guard find_planned_file(files, "moon.proton") is Some(config) else {
    abort("missing moon.proton")
  }
  assert_true(config.contains("product_name = \"Demo App\""))
  assert_true(config.contains("identifier = \"com.justjavac.demo\""))
  assert_true(config.contains("title: \"Demo App\""))
  assert_true(config.contains("width: 1000"))
  assert_true(config.contains("height: 700"))
  assert_true(config.contains("path: \"backend\""))
  assert_true(config.contains("package: \"app\""))
  assert_true(config.contains("path: \"frontend\""))
  assert_true(config.contains("before_dev: \"warren dev --port 4300\""))
  assert_true(config.contains("value: \"frontend/dist/index.html\""))
  assert_true(config.contains("bundle = {"))
  assert_true(config.contains("active: true"))
  assert_true(config.contains("targets: [\"app\", \"zip\"]"))
  assert_true(config.contains("output: \"target/proton-dist\""))
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
  assert_true(readme.contains("proton_cli dev"))
  assert_true(readme.contains("## Build"))
  assert_true(readme.contains("proton_cli build"))
  assert_true(readme.contains("## Bundle"))
  assert_true(readme.contains("shared/"))
  assert_true(readme.contains("proton_cli package --dry-run"))
}

///|
test "user title can contain template braces" {
  let files = must_plan(
    must_options(["demo", "--title", "A {{ Demo }}", "--author", "braces"]),
  )
  guard find_planned_file(files, "moon.proton") is Some(config) else {
    abort("missing moon.proton")
  }
  assert_true(config.contains("product_name = \"A {{ Demo }}\""))
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

///|
test "registry dependency failures are classified separately" {
  assert_true(
    moon_check_has_registry_resolution_failure(
      "Failed to resolve registry dependency `moonbit-community/proton_contract`",
    ),
  )
  assert_true(
    moon_check_has_registry_resolution_failure(
      "failed to resolve registry dependency `moonbit-community/proton_client`",
    ),
  )
  assert_false(
    moon_check_has_registry_resolution_failure("Parsing error: UnexpectedToken"),
  )
  let error = NewProjectToolError::RegistryDependenciesUnavailable(
    code=255,
    project="todo",
  )
  let message = error.message()
  assert_true(message.contains("moonbit-community/proton_contract@0.1.1"))
  assert_true(message.contains("moonbit-community/proton_client@0.1.1"))
  assert_true(message.contains("moonbit-community/proton_rabbita@0.1.1"))
  assert_true(message.contains("moonbit-community/proton@0.1.14"))
  assert_true(
    message.contains(
      "moonbit-community/proton_cli@" + default_proton_cli_version,
    ),
  )
  assert_true(message.contains("project was rolled back"))
}

///|
async test "project generation commits a complete staged tree" {
  let options = transaction_test_options(
    "target/proton-new-transaction-success",
  )
  remove_new_test_tree(options.resolved_target_dir)
  let files = must_plan(options)
  create_project(options, files)
  assert_true(
    @fsutil.path_exists(
      @fsutil.path_join(options.resolved_target_dir, "moon.work"),
    ),
  )
  assert_true(
    @fsutil.path_exists(
      @fsutil.path_join(options.resolved_target_dir, "backend/app/main.mbt"),
    ),
  )
  let staging = @fsutil.path_join(
    @fsutil.path_parent(options.resolved_target_dir),
    staging_directory_name(options.resolved_target_dir, 0),
  )
  assert_false(@fsutil.path_exists(staging))
  remove_new_test_tree(options.resolved_target_dir)
}

///|
async test "failed project writes leave no target or staging tree" {
  let options = transaction_test_options("target/proton-new-transaction-failed")
  remove_new_test_tree(options.resolved_target_dir)
  let files = [
    PlannedFile::{ path: "blocked", content: "file" },
    PlannedFile::{ path: "blocked/child", content: "child" },
  ]
  try create_project(options, files) catch {
    NewProjectWriteError::WriteFile(..) => ()
    error => abort("expected write failure, got " + error.to_string())
  } noraise {
    _ => abort("expected project generation to fail")
  }
  assert_false(@fsutil.path_exists(options.resolved_target_dir))
  let staging = @fsutil.path_join(
    @fsutil.path_parent(options.resolved_target_dir),
    staging_directory_name(options.resolved_target_dir, 0),
  )
  assert_false(@fsutil.path_exists(staging))
}

///|
async test "failed project writes restore an existing empty target" {
  let options = transaction_test_options(
    "target/proton-new-transaction-empty-target",
  )
  remove_new_test_tree(options.resolved_target_dir)
  ensure_dir_recursive(options.resolved_target_dir)
  let files = [
    PlannedFile::{ path: "blocked", content: "file" },
    PlannedFile::{ path: "blocked/child", content: "child" },
  ]
  try create_project(options, files) catch {
    NewProjectWriteError::WriteFile(..) => ()
    error => abort("expected write failure, got " + error.to_string())
  } noraise {
    _ => abort("expected project generation to fail")
  }
  assert_true(@fsutil.path_is_dir(options.resolved_target_dir))
  assert_true(target_dir_is_empty(options.resolved_target_dir))
  remove_new_test_tree(options.resolved_target_dir)
}

///|
async test "cancelled project generation removes its staging tree" {
  let options = transaction_test_options(
    "target/proton-new-transaction-cancelled",
  )
  remove_new_test_tree(options.resolved_target_dir)
  let outcome = @async.with_timeout_opt(0, () => {
    create_project(options, must_plan(options))
  })
  assert_true(outcome is None)
  assert_false(@fsutil.path_exists(options.resolved_target_dir))
  let staging = @fsutil.path_join(
    @fsutil.path_parent(options.resolved_target_dir),
    staging_directory_name(options.resolved_target_dir, 0),
  )
  assert_false(@fsutil.path_exists(staging))
}

///|
async test "moon check failure is rolled back before publication" {
  let raw = must_parse([
    "target/proton-new-transaction-check-failed", "--check", "--no-git",
  ])
  let options = options_from_raw(".", raw)
  remove_new_test_tree(options.resolved_target_dir)
  try
    create_project(options, [
      PlannedFile::{ path: "moon.mod", content: "name =" },
    ])
  catch {
    NewProjectToolError::MoonCheckFailed(..) => ()
    error => abort("expected moon check failure, got " + error.to_string())
  } noraise {
    _ => abort("expected project validation to fail")
  }
  assert_false(@fsutil.path_exists(options.resolved_target_dir))
  let staging = @fsutil.path_join(
    @fsutil.path_parent(options.resolved_target_dir),
    staging_directory_name(options.resolved_target_dir, 0),
  )
  assert_false(@fsutil.path_exists(staging))
}
