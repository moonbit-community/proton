///|
struct RawNewProjectOptions {
  path : String?
  title : String?
  module_name : String?
  width : String?
  height : String?
  check : Bool?
  yes : Bool
  git : Bool?
  dry_run : Bool
} derive(Debug, Eq)

///|
struct NewProjectOptions {
  cwd : String
  target_dir : String
  resolved_target_dir : String
  title : String
  module_name : String
  width : Int
  height : Int
  run_check : Bool
  yes : Bool
  git : Bool?
  dry_run : Bool
} derive(Debug, Eq)

///|
pub async fn run(cwd : String, args : Array[String]) -> Result[Unit, String] {
  let cwd = @path.Path(cwd).resolve().to_string()
  let raw = parse_new_args(args) catch { err => return Err(err.to_string()) }
  let defaults = match options_from_raw(cwd, raw) {
    Ok(options) => options
    Err(message) => return Err(message)
  }
  let interactive = !raw.yes && !@ci.is_ci(cwd~)
  let options = if interactive {
    let prompted = match prompt_new_project_options(raw, defaults) {
      Ok(options) => options
      Err(message) => return Err(message)
    }
    if !confirm_create(prompted) {
      println("Cancelled.")
      return Ok(())
    }
    prompted
  } else {
    defaults
  }
  let files = match
    plan_project_files(
      options.title,
      options.module_name,
      options.width,
      options.height,
    ) {
    Ok(files) => files
    Err(message) => return Err(message)
  }
  if options.dry_run {
    print_dry_run(options, files)
    return Ok(())
  }
  match write_project(options, files) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  match maybe_init_git(options) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  if options.run_check {
    run_moon_check(options)
  } else {
    print_success(options, checked=false)
    Ok(())
  }
}

///|
fn new_arg_parser() -> @argparse.Command {
  @argparse.Command(
    "proton_cli new",
    about="Create a new Proton native desktop app",
    flags=[
      FlagArg(
        "check",
        long="check",
        negatable=true,
        about="Run moon check after creation",
      ),
      FlagArg(
        "yes",
        short='y',
        long="yes",
        about="Accept defaults and skip prompts",
      ),
      FlagArg(
        "git",
        long="git",
        negatable=true,
        about="Initialize a git repository",
      ),
      FlagArg(
        "dry-run",
        long="dry-run",
        about="Print files without writing them",
      ),
    ],
    options=[
      OptionArg("title", long="title", about="Application and window title"),
      OptionArg("module", long="module", about="moon.mod module name"),
      OptionArg("width", long="width", about="Window width in pixels"),
      OptionArg("height", long="height", about="Window height in pixels"),
    ],
    positionals=[
      PositionArg(
        "path",
        about="Project directory",
        num_args=ValueRange(lower=0, upper=1),
      ),
    ],
  )
}

///|
fn parse_new_args(args : Array[String]) -> RawNewProjectOptions raise {
  let matches = new_arg_parser().parse(argv=args, env={})
  {
    path: match_value(matches, "path"),
    title: match_value(matches, "title"),
    module_name: match_value(matches, "module"),
    width: match_value(matches, "width"),
    height: match_value(matches, "height"),
    check: match_flag(matches, "check"),
    yes: match_flag(matches, "yes").unwrap_or(false),
    git: match_flag(matches, "git"),
    dry_run: match_flag(matches, "dry-run").unwrap_or(false),
  }
}

///|
fn match_value(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
fn match_flag(matches : @argparse.Matches, name : String) -> Bool? {
  match matches.flags.get(name) {
    Some(value) => Some(value)
    None => None
  }
}

///|
fn options_from_raw(
  cwd : String,
  raw : RawNewProjectOptions,
) -> Result[NewProjectOptions, String] {
  let target_dir = raw.path.unwrap_or(default_project_path)
  let slug = project_slug(cwd, target_dir)
  let title = raw.title.unwrap_or(slug_to_title(slug))
  let module_name = raw.module_name.unwrap_or(slug)
  let width = match raw.width {
    Some(value) =>
      match parse_positive_int(value, "width") {
        Ok(width) => width
        Err(message) => return Err(message)
      }
    None => default_width
  }
  let height = match raw.height {
    Some(value) =>
      match parse_positive_int(value, "height") {
        Ok(height) => height
        Err(message) => return Err(message)
      }
    None => default_height
  }
  let run_check = raw.check.unwrap_or(true)
  let options = NewProjectOptions::{
    cwd,
    target_dir,
    resolved_target_dir: resolve_new_path(cwd, target_dir),
    title,
    module_name,
    width,
    height,
    run_check,
    yes: raw.yes,
    git: raw.git,
    dry_run: raw.dry_run,
  }
  validate_options(options)
}

///|
fn validate_options(
  options : NewProjectOptions,
) -> Result[NewProjectOptions, String] {
  match validate_target_dir(options.target_dir) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  match validate_title(options.title) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  match validate_module_name(options.module_name) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  Ok(options)
}

///|
fn print_dry_run(
  options : NewProjectOptions,
  files : Array[PlannedFile],
) -> Unit {
  println("Would create Proton project at " + options.target_dir)
  println("")
  for file in files {
    println("  " + file.path)
  }
}

///|
fn write_project(
  options : NewProjectOptions,
  files : Array[PlannedFile],
) -> Result[Unit, String] {
  match validate_target_dir_for_write(options.resolved_target_dir) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  match ensure_dir_recursive(options.resolved_target_dir) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  for file in files {
    let output_path = project_file_path(options.resolved_target_dir, file.path)
    match ensure_file_parent(output_path) {
      Ok(_) => ()
      Err(message) => return Err(message)
    }
    @mbfs.write_string_to_file(output_path, file.content, encoding="utf8") catch {
      err =>
        return Err(
          "failed to write " +
          output_path +
          ": " +
          @debug.render(@debug.to_repr(err)),
        )
    }
  }
  Ok(())
}

///|
fn project_file_path(root : String, relative : String) -> String {
  let mut current = root
  for part in relative.split("/") {
    current = new_path_join(current, part.to_owned())
  }
  current
}

///|
fn ensure_file_parent(path : String) -> Result[Unit, String] {
  let parent = new_path_parent(path)
  if parent == path || parent == "" || path_exists(parent) {
    return Ok(())
  }
  ensure_dir_recursive(parent)
}

///|
fn ensure_dir_recursive(path : String) -> Result[Unit, String] {
  if path == "" || path_exists(path) {
    return Ok(())
  }
  let parent = new_path_parent(path)
  if parent != "" && parent != path {
    match ensure_dir_recursive(parent) {
      Ok(_) => ()
      Err(message) => return Err(message)
    }
  }
  @mbfs.create_dir(path) catch {
    err =>
      return Err(
        "failed to create " + path + ": " + @debug.render(@debug.to_repr(err)),
      )
  }
  Ok(())
}

///|
fn new_path_parent(path : String) -> String {
  let normalized = if path.has_suffix("\\") || path.has_suffix("/") {
    path.unsafe_substring(start=0, end=path.length() - 1)
  } else {
    path
  }
  let slash = normalized.rev_find("/")
  let backslash = normalized.rev_find("\\")
  let index = match (slash, backslash) {
    (Some(a), Some(b)) => Some(if a > b { a } else { b })
    (Some(a), None) => Some(a)
    (None, Some(b)) => Some(b)
    (None, None) => None
  }
  match index {
    Some(index) if index > 0 =>
      normalized.unsafe_substring(start=0, end=index).to_string()
    _ => ""
  }
}

///|
async fn maybe_init_git(options : NewProjectOptions) -> Result[Unit, String] {
  match options.git {
    Some(true) => {
      let code = @process.run("git", ["init"], cwd=options.resolved_target_dir) catch {
        err =>
          return Err(
            "failed to run git init: " + @debug.render(@debug.to_repr(err)),
          )
      }
      if code == 0 {
        Ok(())
      } else {
        Err("git init failed with exit code " + code.to_string())
      }
    }
    _ => Ok(())
  }
}

///|
async fn run_moon_check(options : NewProjectOptions) -> Result[Unit, String] {
  let code = @process.run("moon", [
    "-C",
    options.resolved_target_dir,
    "check",
    "--target",
    "native",
    "--diagnostic-limit",
    "80",
  ]) catch {
    err =>
      return Err(
        "failed to run moon check: " + @debug.render(@debug.to_repr(err)),
      )
  }
  if code == 0 {
    print_success(options, checked=true)
    Ok(())
  } else {
    Err(
      "project was created, but moon check failed with exit code " +
      code.to_string() +
      "\n\nRetry with:\n  cd " +
      options.target_dir +
      "\n  moon check --target native --diagnostic-limit 80",
    )
  }
}

///|
fn print_success(options : NewProjectOptions, checked~ : Bool) -> Unit {
  println("Created Proton project at " + options.target_dir)
  if checked {
    println("moon check completed successfully.")
  }
  println("")
  println("Next steps:")
  println("  cd " + options.target_dir)
  println("  proton_cli cef setup")
  println("  proton_cli dev")
}
