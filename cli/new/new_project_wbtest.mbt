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
test "default new options" {
  let options = must_options([])
  assert_eq(options.target_dir, "todo")
  assert_eq(options.template, "isomorphic")
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
test "template option selects minimal scaffold" {
  let options = must_options(["demo", "--template", "minimal"])
  assert_eq(options.template, "minimal")
}

///|
test "todo is not a template name" {
  try options_from_raw(".", must_parse(["demo", "--template", "todo"])) catch {
    InvalidTemplate(template="todo") => ()
    _ => abort("expected invalid template")
  } noraise {
    _ => abort("expected template to fail")
  }
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
test "project config preserves application identity" {
  let context = template_context(
    "Demo App", "moonbit-community", "demo", "com.justjavac.demo", 1000, 700,
  )
  let config = @json.parse(project_config_file(context, "isomorphic").content) catch {
    error => abort(error.to_string())
  }
  guard config
    is {
      "identifier": "com.justjavac.demo",
      "package": { "product_name": "Demo App", .. },
      ..
    } else {
    abort("project config did not preserve application identity")
  }
}

///|
test "project config uses host-native package format defaults" {
  let context = template_context(
    "Demo App", "moonbit-community", "demo", "com.justjavac.demo", 1000, 700,
  )
  let config = @json.parse(project_config_file(context, "isomorphic").content) catch {
    error => abort(error.to_string())
  }
  guard config is { "package": { "formats"? : None, .. }, .. } else {
    abort("generated project config fixed package formats to one platform")
  }
}

///|
test "isomorphic README documents host-native package defaults" {
  let context = template_context(
    "Demo App", "moonbit-community", "demo", "com.justjavac.demo", 1000, 700,
  )
  let mut readme : String? = None
  for spec in generated_isomorphic_template_specs() {
    if spec.output_path == "README.md" {
      readme = Some(render_template(spec, context).content)
    }
  }
  guard readme is Some(readme) else {
    abort("isomorphic template did not include README.md")
  }
  let package_and_rest = match readme.split_once("## Package\n\n") {
    Some((_, package_and_rest)) => package_and_rest
    None => abort("isomorphic README did not include the Package section")
  }
  let package_section = match package_and_rest.split_once("\n## Layout\n") {
    Some((package_section, _)) => package_section
    None => abort("isomorphic README did not terminate the Package section")
  }
  inspect(
    package_section.to_owned(),
    content=(
      #|The top-level `identifier` is the application's canonical identity. The
      #|`package` block contains the remaining static packaging metadata:
      #|
      #|```json
      #|{
      #|  "identifier": "com.example.my-app",
      #|  "package": {
      #|    "product_name": "My App",
      #|    "version": "0.1.0",
      #|    "output": "dist"
      #|  }
      #|}
      #|```
      #|
      #|When `formats` is omitted, Proton selects the current host's default package
      #|formats. Use `package.platforms` for platform-specific formats, resources, or
      #|signing targets.
      #|
      #|Window behavior, the asset entry, single-instance handling, and renderer
      #|permissions are declared by the Proton `App` builder in `backend/app/main.mbt`.
      #|
      #|Inspect the resolved package plan, then create the current host's native
      #|artifacts:
      #|
      #|```sh
      #|proton_cli package --dry-run
      #|proton_cli package --release
      #|```
      #|
    ),
  )
}

///|
test "isomorphic project config pins Warren browser entry" {
  let context = template_context(
    "Demo App", "moonbit-community", "demo", "com.justjavac.demo", 1000, 700,
  )
  let content = project_config_file(context, "isomorphic").content
  assert_true(content.contains("dev --browser-entry main"))
  assert_true(content.contains("build --browser-entry main"))
}

///|
test "minimal project config uses a single backend module" {
  let context = template_context(
    "Demo App", "moonbit-community", "demo", "com.justjavac.demo", 1000, 700,
  )
  let config = @json.parse(project_config_file(context, "minimal").content) catch {
    error => abort(error.to_string())
  }
  guard config
    is {
      "backend": { "path": ".", "package": "app", .. },
      "frontend"? : None,
      ..
    } else {
    abort("minimal project config did not use a single backend module")
  }
}

///|
test "template renderer preserves replacement delimiters and escapes values" {
  let context = template_context(
    "A {{ Demo }} \"<&", "username", "demo", "dev.proton.demo", 960, 640,
  )
  let rendered = render_template(
    {
      output_path: "rendered",
      template_name: "rendered.tmpl",
      template_source: "{{title}}\n{{title_mbt}}\n{{title_html}}",
    },
    context,
  )
  inspect(
    rendered.content,
    content=(
      #|A {{ Demo }} "<&
      #|"A {{ Demo }} \"<&"
      #|A {{ Demo }} &quot;&lt;&amp;
    ),
  )
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
