///|
async fn prompt_text(label : String, default : String) -> String {
  println(label + " [" + default + "]:")
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
  println(label + " [" + suffix + "]:")
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
) -> Result[NewProjectOptions, String] {
  let target_dir = prompt_text("Project directory", defaults.target_dir)
  let slug = project_slug(defaults.cwd, target_dir)
  let title_default = raw.title.unwrap_or(slug_to_title(slug))
  let module_default = raw.module_name.unwrap_or(slug)
  let identifier_default = raw.identifier.unwrap_or(
    default_bundle_identifier(slug),
  )
  let title = prompt_text("App title", title_default)
  let module_name = prompt_text("Module name", module_default)
  let identifier = prompt_text("Bundle identifier", identifier_default)
  let width_text = prompt_text("Window width", defaults.width.to_string())
  let height_text = prompt_text("Window height", defaults.height.to_string())
  let run_check = prompt_bool(
    "Run moon check after creation",
    defaults.run_check,
  )
  let width = match parse_positive_int(width_text, "width") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let height = match parse_positive_int(height_text, "height") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let next = NewProjectOptions::{
    ..defaults,
    target_dir,
    resolved_target_dir: resolve_new_path(defaults.cwd, target_dir),
    title,
    module_name,
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
  println("App title: " + options.title)
  println("Module name: " + options.module_name)
  println("Bundle identifier: " + options.identifier)
  println(
    "Window: " + options.width.to_string() + "x" + options.height.to_string(),
  )
  println("Counter extension: extensions/counter")
  let check_text = if options.run_check { "yes" } else { "no" }
  println("Run moon check: " + check_text)
  println("")
  prompt_bool("Create project?", true)
}
