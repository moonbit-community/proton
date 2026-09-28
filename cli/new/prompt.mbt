///|
async fn prompt_text(label : String, default : String) -> String {
  @stdio.stdout.write(label + " [" + default + "]: ")
  match @stdio.stdin.read_until("\n") {
    Some(line) => {
      let value = line.trim().to_owned()
      if value == "" {
        default
      } else {
        value
      }
    }
    None => default
  }
}

///|
async fn prompt_bool(label : String, default : Bool) -> Bool {
  let suffix = if default { "Y/n" } else { "y/N" }
  @stdio.stdout.write(label + " [" + suffix + "]: ")
  match @stdio.stdin.read_until("\n") {
    Some(line) => {
      let value = line.trim().to_owned().to_lower()
      match value {
        "" => default
        "y" | "yes" | "true" | "1" => true
        "n" | "no" | "false" | "0" => false
        _ => default
      }
    }
    None => default
  }
}

///|
async fn prompt_new_project_options(
  raw : RawNewProjectOptions,
  defaults : NewProjectOptions,
  prompt_text? : async (String, String) -> String = prompt_text,
  prompt_bool? : async (String, Bool) -> Bool = prompt_bool,
) -> NewProjectOptions {
  let template = match raw.template {
    Some(_) => defaults.template
    None =>
      parse_project_template(
        prompt_text("Template (minimal/isomorphic)", defaults.template),
      )
  }
  let target_dir = match raw.path {
    Some(_) => defaults.target_dir
    None => prompt_text("Project directory", defaults.target_dir)
  }
  let slug = project_slug(defaults.cwd, target_dir)
  let title = match raw.title {
    Some(_) => defaults.title
    None => prompt_text("App title", slug_to_title(slug))
  }
  let author = match raw.author {
    Some(_) => defaults.author
    None => prompt_text("Module author", default_author)
  }
  let identifier = match raw.identifier {
    Some(_) => defaults.identifier
    None => prompt_text("Bundle identifier", default_bundle_identifier(slug))
  }
  let width_text = match raw.width {
    Some(value) => value
    None => prompt_text("Window width", defaults.width.to_string())
  }
  let height_text = match raw.height {
    Some(value) => value
    None => prompt_text("Window height", defaults.height.to_string())
  }
  let run_check = match raw.check {
    Some(value) => value
    None => prompt_bool("Run moon check after creation", defaults.run_check)
  }
  let width = parse_positive_int(width_text, "width")
  let height = parse_positive_int(height_text, "height")
  let next = NewProjectOptions::{
    ..defaults,
    template,
    target_dir,
    resolved_target_dir: @fsutil.resolve_path(defaults.cwd, target_dir),
    title,
    author,
    project_name: slug,
    identifier,
    width,
    height,
    run_check,
  }
  validate_options(next)
}

///|
async fn confirm_create(options : NewProjectOptions) -> Bool {
  println("")
  println("Project directory: " + options.target_dir)
  println("Template: " + options.template)
  println("App title: " + options.title)
  println("Module author: " + options.author)
  if options.template == "minimal" {
    println("App module: " + options.author + "/" + options.project_name)
  } else {
    println(
      "Shared module: " +
      options.author +
      "/" +
      options.project_name +
      "_shared",
    )
    println(
      "Frontend module: " +
      options.author +
      "/" +
      options.project_name +
      "_frontend",
    )
    println(
      "Backend module: " +
      options.author +
      "/" +
      options.project_name +
      "_backend",
    )
  }
  println("Bundle identifier: " + options.identifier)
  println(
    "Window: " + options.width.to_string() + "x" + options.height.to_string(),
  )
  println("Architecture: " + template_architecture(options.template))
  let check_text = if options.run_check { "yes" } else { "no" }
  println("Run moon check: " + check_text)
  println("")
  prompt_bool("Create project?", true)
}
