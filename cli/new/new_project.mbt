///|
struct RawNewProjectOptions {
  path : String?
  title : String?
  module_name : String?
  identifier : String?
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
  identifier : String
  width : Int
  height : Int
  run_check : Bool
  yes : Bool
  git : Bool?
  dry_run : Bool
} derive(Debug, Eq)

///|
/// Creates a project from parsed `proton_cli new` command matches.
pub async fn run(cwd : String, matches : @argparse.Matches) -> Unit {
  let cwd = @path.Path(cwd).resolve().to_string()
  let raw = new_options_from_matches(matches)
  let defaults = options_from_raw(cwd, raw)
  let interactive = !raw.yes && !@ci.is_ci(cwd~)
  let options = if interactive {
    let prompted = prompt_new_project_options(raw, defaults)
    if !confirm_create(prompted) {
      println("Cancelled.")
      return
    }
    prompted
  } else {
    defaults
  }
  let files = plan_project_files(
    options.title,
    options.module_name,
    options.identifier,
    options.width,
    options.height,
  )
  if options.dry_run {
    print_dry_run(options, files)
    return
  }
  write_project(options, files)
  maybe_init_git(options)
  if options.run_check {
    run_moon_check(options)
  } else {
    print_success(options, checked=false)
  }
}

///|
/// Returns the declarative `proton_cli new` command specification.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "new",
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
      OptionArg(
        "identifier",
        long="identifier",
        about="Reverse-DNS application bundle identifier",
      ),
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
fn new_options_from_matches(
  matches : @argparse.Matches,
) -> RawNewProjectOptions {
  {
    path: @cli_args.value(matches, "path"),
    title: @cli_args.value(matches, "title"),
    module_name: @cli_args.value(matches, "module"),
    identifier: @cli_args.value(matches, "identifier"),
    width: @cli_args.value(matches, "width"),
    height: @cli_args.value(matches, "height"),
    check: @cli_args.optional_flag(matches, "check"),
    yes: @cli_args.flag(matches, "yes"),
    git: @cli_args.optional_flag(matches, "git"),
    dry_run: @cli_args.flag(matches, "dry-run"),
  }
}

///|
fn options_from_raw(
  cwd : String,
  raw : RawNewProjectOptions,
) -> NewProjectOptions raise NewProjectInputError {
  let target_dir = raw.path.unwrap_or(default_project_path)
  let slug = project_slug(cwd, target_dir)
  let title = raw.title.unwrap_or(slug_to_title(slug))
  let module_name = raw.module_name.unwrap_or(slug)
  let identifier = raw.identifier.unwrap_or(default_bundle_identifier(slug))
  let width = match raw.width {
    Some(value) => parse_positive_int(value, "width")
    None => default_width
  }
  let height = match raw.height {
    Some(value) => parse_positive_int(value, "height")
    None => default_height
  }
  let run_check = raw.check.unwrap_or(true)
  let options = NewProjectOptions::{
    cwd,
    target_dir,
    resolved_target_dir: resolve_new_path(cwd, target_dir),
    title,
    module_name,
    identifier,
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
) -> NewProjectOptions raise NewProjectInputError {
  validate_target_dir(options.target_dir)
  validate_title(options.title)
  validate_module_name(options.module_name)
  validate_bundle_identifier(options.identifier)
  options
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
) -> Unit raise {
  validate_target_dir_for_write(options.resolved_target_dir)
  ensure_dir_recursive(options.resolved_target_dir)
  for file in files {
    let output_path = project_file_path(options.resolved_target_dir, file.path)
    ensure_file_parent(output_path)
    @mbfs.write_string_to_file(output_path, file.content, encoding="utf8") catch {
      err =>
        raise NewProjectWriteError::WriteFile(
          path=output_path,
          detail=@debug.render(@debug.to_repr(err)),
        )
    }
  }
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
fn ensure_file_parent(path : String) -> Unit raise NewProjectWriteError {
  let parent = new_path_parent(path)
  if parent == path || parent == "" || path_exists(parent) {
    return
  }
  ensure_dir_recursive(parent)
}

///|
fn ensure_dir_recursive(path : String) -> Unit raise NewProjectWriteError {
  if path == "" || path_exists(path) {
    return
  }
  let parent = new_path_parent(path)
  if parent != "" && parent != path {
    ensure_dir_recursive(parent)
  }
  @mbfs.create_dir(path) catch {
    err =>
      raise CreateDirectory(path~, detail=@debug.render(@debug.to_repr(err)))
  }
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
async fn maybe_init_git(
  options : NewProjectOptions,
) -> Unit raise NewProjectToolError {
  match options.git {
    Some(true) => {
      let code = @process.run("git", ["init"], cwd=options.resolved_target_dir) catch {
        err =>
          raise Start(
            tool="git init",
            detail=@debug.render(@debug.to_repr(err)),
          )
      }
      if code != 0 {
        raise Exit(tool="git init", code~)
      }
    }
    _ => ()
  }
}

///|
async fn run_moon_check(
  options : NewProjectOptions,
) -> Unit raise NewProjectToolError {
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
      raise Start(tool="moon check", detail=@debug.render(@debug.to_repr(err)))
  }
  if code == 0 {
    print_success(options, checked=true)
  } else {
    raise MoonCheckFailed(code~, project=options.target_dir)
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
  println("  proton_cli build")
  println("  proton_cli package --dry-run")
  println("  proton_cli package")
}
