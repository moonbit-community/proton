///|
struct RawNewProjectOptions {
  path : String?
  title : String?
  author : String?
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
  author : String
  project_name : String
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
    options.author,
    options.project_name,
    options.identifier,
    options.width,
    options.height,
  )
  if options.dry_run {
    print_dry_run(options, files)
    return
  }
  create_project(options, files)
  print_success(options, checked=options.run_check)
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
      OptionArg("author", long="author", about="MoonBit module author"),
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
    author: @cli_args.value(matches, "author"),
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
  let author = raw.author.unwrap_or(default_author)
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
    author,
    project_name: slug,
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
  validate_author(options.author)
  validate_module_name(options.author + "/" + options.project_name + "_shared")
  validate_module_name(
    options.author + "/" + options.project_name + "_frontend",
  )
  validate_module_name(options.author + "/" + options.project_name + "_backend")
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
async fn create_project(
  options : NewProjectOptions,
  files : Array[PlannedFile],
) -> Unit {
  validate_target_dir_for_write(options.resolved_target_dir)
  let target_existed = path_exists(options.resolved_target_dir)
  let target_parent = new_path_parent(options.resolved_target_dir)
  let existing_ancestor = nearest_existing_ancestor(target_parent)
  let mut staging_dir = ""
  @async.protect_from_cancel(() => {
    staging_dir = reserve_staging_directory(
      existing_ancestor,
      options.resolved_target_dir,
    )
  }) catch {
    error => {
      let rollback_failures : Array[String] = []
      @async.protect_from_cancel(resume_on_cancel=true, () => {
        remove_transaction_tree(staging_dir, rollback_failures)
      })
      if rollback_failures.length() > 0 {
        raise NewProjectWriteError::Rollback(
          primary=@debug.render(Repr(error)),
          detail=rollback_failures.join("; "),
        )
      }
      raise error
    }
  }
  try {
    write_project_files(staging_dir, files)
    maybe_init_git(options, staging_dir)
    if options.run_check {
      run_moon_check(options, staging_dir)
    }
    commit_project(
      staging_dir,
      options.resolved_target_dir,
      target_parent,
      target_existed,
    )
  } catch {
    error => {
      let rollback_failures : Array[String] = []
      @async.protect_from_cancel(resume_on_cancel=true, () => {
        remove_transaction_tree(staging_dir, rollback_failures)
        if target_existed && !path_exists(options.resolved_target_dir) {
          restore_empty_target(options.resolved_target_dir, rollback_failures)
        }
        remove_created_parent_directories(
          target_parent, existing_ancestor, rollback_failures,
        )
      })
      if rollback_failures.length() > 0 {
        raise NewProjectWriteError::Rollback(
          primary=@debug.render(Repr(error)),
          detail=rollback_failures.join("; "),
        )
      }
      raise error
    }
  }
}

///|
async fn write_project_files(
  staging_dir : String,
  files : Array[PlannedFile],
) -> Unit {
  for file in files {
    let output_path = project_file_path(staging_dir, file.path)
    ensure_file_parent(output_path)
    @async_fs.write_file(
      output_path,
      file.content,
      create_mode=CreateOrTruncate,
    ) catch {
      err =>
        raise NewProjectWriteError::WriteFile(
          path=output_path,
          detail=@debug.render(Repr(err)),
        )
    }
  }
}

///|
async fn nearest_existing_ancestor(path : String) -> String {
  let mut current = path
  while current != "" && !path_exists(current) {
    let parent = new_path_parent(current)
    if parent == current {
      break
    }
    current = parent
  }
  if current == "" {
    raise NewProjectWriteError::CreateDirectory(
      path~,
      detail="no existing ancestor directory",
    )
  }
  current
}

///|
fn staging_directory_name(target_dir : String, attempt : Int) -> String {
  "." +
  path_basename(target_dir) +
  ".proton-new-" +
  attempt.to_string() +
  ".tmp"
}

///|
async fn reserve_staging_directory(
  existing_ancestor : String,
  target_dir : String,
) -> String {
  for attempt in 0..<1024 {
    let staging_dir = new_path_join(
      existing_ancestor,
      staging_directory_name(target_dir, attempt),
    )
    if path_exists(staging_dir) {
      continue
    }
    let created = try {
      @async_fs.mkdir(staging_dir)
      true
    } catch {
      error =>
        if path_exists(staging_dir) {
          false
        } else {
          raise NewProjectWriteError::CreateDirectory(
            path=staging_dir,
            detail=@debug.render(Repr(error)),
          )
        }
    }
    if created {
      return staging_dir
    }
  }
  raise NewProjectWriteError::CreateDirectory(
    path=existing_ancestor,
    detail="could not reserve a staging directory after 1024 attempts",
  )
}

///|
async fn commit_project(
  staging_dir : String,
  target_dir : String,
  target_parent : String,
  target_existed : Bool,
) -> Unit {
  ensure_dir_recursive(target_parent)
  if target_existed {
    validate_target_dir_for_write(target_dir)
    @async_fs.rmdir(target_dir, recursive=false) catch {
      error =>
        raise NewProjectWriteError::Commit(
          target=target_dir,
          detail="failed to remove the existing empty target: " +
            @debug.render(Repr(error)),
        )
    }
  }
  @async_fs.rename(staging_dir, target_dir, replace=false) catch {
    error =>
      raise NewProjectWriteError::Commit(
        target=target_dir,
        detail=@debug.render(Repr(error)),
      )
  }
}

///|
async fn remove_transaction_tree(
  path : String,
  failures : Array[String],
) -> Unit {
  if path == "" || !path_exists(path) {
    return
  }
  @async_fs.rmdir(path, recursive=true) catch {
    error => failures.push("remove " + path + ": " + @debug.render(Repr(error)))
  }
}

///|
async fn restore_empty_target(
  target_dir : String,
  failures : Array[String],
) -> Unit {
  @async_fs.mkdir(target_dir) catch {
    error =>
      failures.push(
        "restore empty target " + target_dir + ": " + @debug.render(Repr(error)),
      )
  }
}

///|
async fn remove_created_parent_directories(
  start : String,
  existing_ancestor : String,
  failures : Array[String],
) -> Unit {
  let mut current = start
  while current != "" && current != existing_ancestor {
    if !path_exists(current) {
      current = new_path_parent(current)
      continue
    }
    if !path_is_dir(current) {
      return
    }
    let entries = @async_fs.readdir(
      current,
      include_hidden=true,
      include_special=false,
    ) catch {
      error => {
        failures.push("inspect " + current + ": " + @debug.render(Repr(error)))
        return
      }
    }
    if entries.length() > 0 {
      return
    }
    @async_fs.rmdir(current, recursive=false) catch {
      error => {
        failures.push(
          "remove empty directory " +
          current +
          ": " +
          @debug.render(Repr(error)),
        )
        return
      }
    }
    current = new_path_parent(current)
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
async fn ensure_file_parent(path : String) -> Unit {
  let parent = new_path_parent(path)
  if parent == path || parent == "" || path_exists(parent) {
    return
  }
  ensure_dir_recursive(parent)
}

///|
async fn ensure_dir_recursive(path : String) -> Unit {
  if path == "" || path_exists(path) {
    return
  }
  let parent = new_path_parent(path)
  if parent != "" && parent != path {
    ensure_dir_recursive(parent)
  }
  @async_fs.mkdir(path) catch {
    err => raise CreateDirectory(path~, detail=@debug.render(Repr(err)))
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
  project_dir : String,
) -> Unit raise NewProjectToolError {
  match options.git {
    Some(true) => {
      let code = @process.run("git", ["init"], cwd=project_dir) catch {
        err => raise Start(tool="git init", detail=@debug.render(Repr(err)))
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
  project_dir : String,
) -> Unit raise NewProjectToolError {
  let (code, data) = @process.collect_output_merged("moon", [
    "-C", project_dir, "check", "--diagnostic-limit", "80",
  ]) catch {
    err => raise Start(tool="moon check", detail=@debug.render(Repr(err)))
  }
  let output = data.text() catch {
    err =>
      raise Start(tool="moon check output", detail=@debug.render(Repr(err)))
  }
  if output != "" {
    @stdio.stderr.write(output) catch {
      _ => ()
    }
  }
  if code != 0 {
    if moon_check_has_registry_resolution_failure(output) {
      raise RegistryDependenciesUnavailable(code~, project=options.target_dir)
    }
    raise MoonCheckFailed(code~, project=options.target_dir)
  }
}

///|
fn moon_check_has_registry_resolution_failure(output : String) -> Bool {
  output.contains("Failed to resolve registry dependency") ||
  output.contains("failed to resolve registry dependency")
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
