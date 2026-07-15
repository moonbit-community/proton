///|
fn print_usage() -> Unit {
  let usage =
    #|Usage:
    #|  proton_cli version
    #|  proton_cli [-C DIR] new [PATH] [--title <title>] [--module <module>] [--width <px>] [--height <px>] [--no-check] [-y|--yes]
    #|  proton_cli [-C DIR] dev [PACKAGE] [--config <path>] [--url <url>] [--command <command>] [--frontend-cwd <dir>] [-- [APP_ARGS]...]
    #|  proton_cli [-C DIR] build [PACKAGE] [--config <path>] [--no-frontend] [-- [MOON_BUILD_ARGS]...]
    #|  proton_cli [-C DIR] package [PACKAGE] [--config <path>] [--target <app|zip>] [--output <dir>] [--no-build] [--dry-run] [--sign] [--notarize]
    #|  proton_cli [-C DIR] doctor [--dry-run] [--verbose] [--deep] [--frontend] [--release] [--run] [--fix] [--json|--json-lines] [--quiet] [--section <name>]... [--output <path>]
    #|  proton_cli codegen <input.mbt> -o <output.g.mbt>
    #|  proton_cli cef setup [--name <cef_binary_name>] [--url <url>]
    #|
    #|Set PROTON_NO_UPDATE_CHECK=1 to skip update checks.
    #|
  println(usage)
}

///|
let cli_current_version : String = "0.1.5"

///|
let cli_manifest_url : String = "https://mooncakes.io/api/v0/manifest/justjavac/proton_cli"

///|
priv struct CliVersion {
  major : Int
  minor : Int
  patch : Int
}

///|
priv enum CliError {
  UsageError(String, Bool)
  CommandError(String)
  ReportedError
}

///|
fn env_flag_is_enabled(value : String) -> Bool {
  match value.trim().to_owned().to_lower() {
    "" | "0" | "false" | "no" | "off" => false
    _ => true
  }
}

///|
fn cli_update_check_disabled() -> Bool {
  match @sys.get_env_var("PROTON_NO_UPDATE_CHECK") {
    Some(value) => env_flag_is_enabled(value)
    None => false
  }
}

///|
fn parse_cli_version_part(part : StringView) -> Int? {
  let text = part.to_owned()
  guard text != "" else { return None }
  let mut value = 0
  for ch in text {
    guard ch.is_ascii_digit() else { return None }
    value = value * 10 + ch.to_int() - '0'.to_int()
  }
  Some(value)
}

///|
fn parse_cli_version(version : String) -> CliVersion? {
  let core = match version.split_once("-") {
    Some((prefix, _)) => prefix.to_owned()
    None => version
  }
  match core.split(".").collect() {
    [major, minor, patch] =>
      match
        (
          parse_cli_version_part(major),
          parse_cli_version_part(minor),
          parse_cli_version_part(patch),
        ) {
        (Some(major), Some(minor), Some(patch)) =>
          Some(CliVersion::{ major, minor, patch })
        _ => None
      }
    _ => None
  }
}

///|
fn compare_cli_version(left : CliVersion, right : CliVersion) -> Int {
  if left.major != right.major {
    left.major.compare(right.major)
  } else if left.minor != right.minor {
    left.minor.compare(right.minor)
  } else {
    left.patch.compare(right.patch)
  }
}

///|
fn cli_version_is_newer(candidate : String, current : String) -> Bool {
  match (parse_cli_version(candidate), parse_cli_version(current)) {
    (Some(candidate), Some(current)) =>
      compare_cli_version(candidate, current) > 0
    _ => false
  }
}

///|
fn latest_version_from_manifest_text(text : String) -> String? {
  let manifest = @json.parse(text) catch { _ => return None }
  match manifest {
    Object(fields) =>
      match fields.get("latest_version") {
        Some(String(version)) => Some(version)
        _ => None
      }
    _ => None
  }
}

///|
fn cli_version_text() -> String {
  "proton_cli " + cli_current_version
}

///|
fn is_cli_version_arg(arg : String) -> Bool {
  arg == "version" || arg == "--version" || arg == "-V"
}

///|
async fn fetch_latest_cli_version() -> String? {
  let (code, output) = @process.collect_output_merged("curl", [
    "-fsSL", "--max-time", "2", cli_manifest_url,
  ]) catch {
    _ => return None
  }
  guard code == 0 else { return None }
  let text = output.text() catch { _ => return None }
  latest_version_from_manifest_text(text)
}

///|
async fn write_stderr_line(message : String) -> Unit {
  @stdio.stderr.write(message + "\n") catch {
    _ => ()
  }
}

///|
async fn check_cli_update() -> Unit {
  guard !cli_update_check_disabled() else { return }
  match fetch_latest_cli_version() {
    Some(latest) =>
      if cli_version_is_newer(latest, cli_current_version) {
        write_stderr_line(
          "warning: proton_cli " +
          latest +
          " is available (current " +
          cli_current_version +
          "). Set PROTON_NO_UPDATE_CHECK=1 to disable this check.",
        )
      }
    None => ()
  }
}

///|
fn print_error_message(message : String) -> Unit {
  if message.has_prefix("error: ") {
    println(message)
  } else {
    println("error: " + message)
  }
}

///|
fn codegen_arg_parser() -> @argparse.Command {
  @argparse.Command(
    "proton_cli codegen",
    about="Generate Proton command extension code from #proton attributes",
    options=[
      OptionArg(
        "output-file",
        short='o',
        about="Output .g.mbt file",
        required=true,
      ),
    ],
    positionals=[
      PositionArg(
        "input_file",
        about="Input MoonBit source file",
        num_args=@argparse.ValueRange::single(),
      ),
    ],
  )
}

///|
fn match_value(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
fn parse_global_args(args : Array[String]) -> (String, Array[String]) {
  let rest : Array[String] = []
  let mut cwd = "."
  let mut index = 0
  while index < args.length() {
    if args[index] == "-C" || args[index] == "--cwd" {
      if index + 1 < args.length() {
        cwd = args[index + 1]
        index = index + 2
      } else {
        rest.push(args[index])
        index = index + 1
        break
      }
    } else {
      break
    }
  }
  for arg in args[index:] {
    rest.push(arg)
  }
  (cwd, rest)
}

///|
fn cli_path_is_absolute(path : String) -> Bool {
  path.has_prefix("\\") ||
  path.has_prefix("/") ||
  path.contains(":\\") ||
  path.contains(":/")
}

///|
fn path_join(base : String, child : String) -> String {
  if base == "" {
    child
  } else if child == "" {
    base
  } else if base.has_suffix("\\") || base.has_suffix("/") {
    base + child
  } else {
    base + @path.sep.to_string() + child
  }
}

///|
fn resolve_cli_path(cwd : String, path : String) -> String {
  if cli_path_is_absolute(path) {
    path
  } else {
    path_join(cwd, path)
  }
}

///|
async fn run_doctor_from_args(
  cwd : String,
  args : Array[String],
) -> Result[Unit, CliError] {
  let mut dry_run = false
  let mut verbose = false
  let mut deep = false
  let mut run_frontend = false
  let mut fix = false
  let mut json = false
  let mut json_lines = false
  let mut quiet = false
  let sections : Array[String] = []
  let mut output : String? = None
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    match arg {
      "--dry-run" => dry_run = true
      "--verbose" => verbose = true
      "--deep" => deep = true
      "--run" => run_frontend = true
      "--fix" => fix = true
      "--frontend" => sections.push("frontend")
      "--release" => sections.push("release")
      "--json" => json = true
      "--json-lines" => json_lines = true
      "--quiet" => quiet = true
      "--section" => {
        guard index + 1 < args.length() else {
          return Err(CliError::UsageError("missing value for --section", false))
        }
        sections.push(args[index + 1])
        index += 1
      }
      "--output" => {
        guard index + 1 < args.length() else {
          return Err(CliError::UsageError("missing value for --output", false))
        }
        output = Some(resolve_cli_path(cwd, args[index + 1]))
        index += 1
      }
      "-h" | "--help" => {
        println(
          "Usage: proton_cli [-C DIR] doctor [--dry-run] [--verbose] [--deep] [--frontend] [--release] [--run] [--fix] [--json|--json-lines] [--quiet] [--section <name>]... [--output <path>]",
        )
        return Ok(())
      }
      _ =>
        return Err(CliError::UsageError("unknown doctor option: " + arg, false))
    }
    index += 1
  }
  if json && json_lines {
    return Err(
      CliError::UsageError(
        "--json and --json-lines are mutually exclusive", false,
      ),
    )
  }
  if quiet && (json || json_lines) {
    return Err(
      CliError::UsageError(
        "--quiet cannot be combined with --json or --json-lines", false,
      ),
    )
  }
  if run_frontend && sections.length() > 0 && !sections.contains("frontend") {
    return Err(
      CliError::UsageError("--run requires the frontend section", false),
    )
  }
  for section in sections {
    if ![
        "project", "environment", "runtime", "platform", "packages", "extensions",
        "app", "frontend", "release",
      ].contains(section) {
      return Err(
        CliError::UsageError("unknown doctor section: " + section, false),
      )
    }
  }
  match
    @doctor.run(
      cwd~,
      dry_run~,
      verbose~,
      deep~,
      run_frontend~,
      fix~,
      json~,
      json_lines~,
      quiet~,
      sections~,
      output~,
    ) {
    Ok(true) => Ok(())
    Ok(false) => Err(CliError::ReportedError)
    Err(message) => Err(CliError::CommandError(message))
  }
}

///|
fn run_codegen(cwd : String, args : Array[String]) -> Result[Unit, CliError] {
  let cmd = codegen_arg_parser()
  let matches = cmd.parse(argv=args, env={}) catch {
    err => return Err(CliError::UsageError(err.to_string(), true))
  }
  let input = match match_value(matches, "input_file") {
    Some(input) => input
    None => return Err(CliError::UsageError("missing input file", false))
  }
  let output = match match_value(matches, "output-file") {
    Some(output) => output
    None => return Err(CliError::UsageError("missing -o <output.g.mbt>", false))
  }
  let resolved_input = resolve_cli_path(cwd, input)
  let resolved_output = resolve_cli_path(cwd, output)
  match @codegen.generate_app_commands_from_file_with_metadata(resolved_input) {
    Err(error) => Err(CliError::CommandError(error))
    Ok(result) => {
      @mbfs.write_string_to_file(
        resolved_output,
        result.source,
        encoding="utf8",
      ) catch {
        err =>
          return Err(CliError::CommandError(@debug.render(@debug.to_repr(err))))
      }
      for warning in result.warnings {
        println("warning: " + warning)
      }
      Ok(())
    }
  }
}

///|
async fn main {
  let argv = @sys.get_cli_args()
  let raw_args = if argv.length() > 0 { argv[1:].to_owned() } else { [] }
  let (cwd, args) = parse_global_args(raw_args)
  if args.length() == 1 && is_cli_version_arg(args[0]) {
    println(cli_version_text())
    return
  }
  check_cli_update()
  if args.length() == 0 || args[0] == "-h" || args[0] == "--help" {
    print_usage()
    return
  }
  let result = if args.length() >= 1 && args[0] == "doctor" {
    run_doctor_from_args(cwd, args[1:].to_owned())
  } else if args.length() >= 1 && args[0] == "new" {
    @new_project.run(cwd, args[1:].to_owned()).map_err(fn(message) {
      CliError::CommandError(message)
    })
  } else if args.length() >= 1 && args[0] == "dev" {
    @dev.run(cwd, args[1:].to_owned()).map_err(fn(error) {
      match error {
        UsageError(message, usage_is_embedded) =>
          CliError::UsageError(message, usage_is_embedded)
        CommandError(message) => CliError::CommandError(message)
      }
    })
  } else if args.length() >= 1 && args[0] == "build" {
    @build.run(cwd, args[1:].to_owned()).map_err(fn(error) {
      match error {
        UsageError(message, usage_is_embedded) =>
          CliError::UsageError(message, usage_is_embedded)
        CommandError(message) => CliError::CommandError(message)
      }
    })
  } else if args.length() >= 1 && args[0] == "package" {
    @package.run(cwd, args[1:].to_owned()).map_err(fn(error) {
      match error {
        UsageError(message, usage_is_embedded) =>
          CliError::UsageError(message, usage_is_embedded)
        CommandError(message) => CliError::CommandError(message)
      }
    })
  } else if args.length() >= 1 && args[0] == "codegen" {
    run_codegen(cwd, args[1:].to_owned())
  } else if args.length() >= 2 && args[0] == "cef" && args[1] == "setup" {
    @cef.run_setup(cwd, args[2:].to_owned()).map_err(fn(error) {
      match error {
        UsageError(message, usage_is_embedded) =>
          CliError::UsageError(message, usage_is_embedded)
        CommandError(message) => CliError::CommandError(message)
      }
    })
  } else {
    Err(CliError::UsageError("unknown command", false))
  }
  match result {
    Ok(_) => ()
    Err(CliError::UsageError(message, usage_is_embedded)) => {
      print_error_message(message)
      if !usage_is_embedded {
        print_usage()
      }
      @sys.exit(1)
    }
    Err(CliError::CommandError(message)) => {
      print_error_message(message)
      @sys.exit(1)
    }
    Err(CliError::ReportedError) => @sys.exit(1)
  }
}
