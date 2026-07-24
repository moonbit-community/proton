///|
let cli_current_version : String = "0.1.9"

///|
let cli_manifest_url : String = "https://mooncakes.io/api/v0/manifest/justjavac/proton_cli"

///|
priv struct CliVersion {
  major : Int
  minor : Int
  patch : Int
}

///|
priv suberror CliUsageError {
  Invalid(message~ : String)
} derive(Debug)

///|
priv suberror CliCodegenOutputError {
  WriteFailed(path~ : String, detail~ : String)
} derive(Debug)

///|
fn CliUsageError::message(self : CliUsageError) -> String {
  match self {
    Invalid(message~) => message
  }
}

///|
fn CliCodegenOutputError::message(self : CliCodegenOutputError) -> String {
  match self {
    WriteFailed(path~, detail~) =>
      "failed to write generated source " + path + ": " + detail
  }
}

///|
impl Show for CliUsageError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
impl Show for CliCodegenOutputError with fn output(self, logger) {
  logger.write_string(self.message())
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
fn codegen_command() -> @argparse.Command {
  @argparse.Command(
    "codegen",
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
fn doctor_command() -> @argparse.Command {
  @argparse.Command(
    "doctor",
    about="Inspect and diagnose a Proton project",
    flags=[
      FlagArg("dry-run", about="Report changes without applying them"),
      FlagArg("verbose", about="Include detailed project diagnostics"),
      FlagArg("deep", about="Run deeper runtime checks"),
      FlagArg("run", about="Select and run frontend diagnostics"),
      FlagArg("fix", about="Select and apply safe automatic fixes"),
      FlagArg("frontend", about="Select the frontend section"),
      FlagArg("release", about="Select the release section"),
      FlagArg("json", about="Render one JSON document", conflicts_with=[
        "json-lines", "quiet",
      ]),
      FlagArg("json-lines", about="Render newline-delimited JSON", conflicts_with=[
        "json", "quiet",
      ]),
      FlagArg("quiet", about="Render only failing diagnostics", conflicts_with=[
        "json", "json-lines",
      ]),
    ],
    options=[
      OptionArg(
        "section",
        action=Append,
        about="Section to inspect; may be repeated",
      ),
      OptionArg("output", about="Write the report to a file"),
    ],
  )
}

///|
fn version_command() -> @argparse.Command {
  @argparse.Command("version", about="Print the Proton CLI version")
}

///|
fn cli_command() -> @argparse.Command {
  @argparse.Command(
    "proton_cli",
    about="Build, run, diagnose, and package Proton desktop applications",
    version=cli_version_text(),
    options=[
      OptionArg(
        "cwd",
        short='C',
        default_values=["."],
        allow_hyphen_values=true,
        global=true,
        about="Run as if started in this directory",
      ),
    ],
    subcommands=[
      version_command(),
      @new_project.command(),
      @dev.command(),
      @build.command(),
      @package.command(),
      doctor_command(),
      codegen_command(),
      @cef.command(),
    ],
    arg_required_else_help=true,
    subcommand_required=true,
  )
}

///|
fn resolve_cli_path(cwd : String, path : String) -> String {
  let candidate : @path.Path = path
  if candidate.is_absolute() {
    candidate.normalize().resolve().to_string()
  } else {
    let base : @path.Path = cwd
    base.join(path).normalize().resolve().to_string()
  }
}

///|
async fn run_doctor(cwd : String, matches : @argparse.Matches) -> Bool {
  let dry_run = @cli_args.flag(matches, "dry-run")
  let verbose = @cli_args.flag(matches, "verbose")
  let deep = @cli_args.flag(matches, "deep")
  let run_frontend = @cli_args.flag(matches, "run")
  let fix = @cli_args.flag(matches, "fix")
  let json = @cli_args.flag(matches, "json")
  let json_lines = @cli_args.flag(matches, "json-lines")
  let quiet = @cli_args.flag(matches, "quiet")
  let sections = @cli_args.values(matches, "section")
  if @cli_args.flag(matches, "frontend") && !sections.contains("frontend") {
    sections.push("frontend")
  }
  if @cli_args.flag(matches, "release") && !sections.contains("release") {
    sections.push("release")
  }
  if run_frontend && !sections.contains("frontend") {
    sections.push("frontend")
  }
  if fix && !sections.contains("fixes") {
    sections.push("fixes")
  }
  if sections.contains("fixes") && !fix {
    raise CliUsageError::Invalid(message="the fixes section requires --fix")
  }
  for section in sections {
    if ![
        "project", "environment", "runtime", "platform", "packages", "extensions",
        "app", "frontend", "release", "fixes",
      ].contains(section) {
      raise CliUsageError::Invalid(message="unknown doctor section: " + section)
    }
  }
  let output = match @cli_args.value(matches, "output") {
    Some(path) => Some(resolve_cli_path(cwd, path))
    None => None
  }
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
  )
}

///|
fn run_codegen(cwd : String, matches : @argparse.Matches) -> Unit raise {
  let input = @cli_args.required_value(matches, "input_file")
  let output = @cli_args.required_value(matches, "output-file")
  let resolved_input = resolve_cli_path(cwd, input)
  let resolved_output = resolve_cli_path(cwd, output)
  let result = @codegen.generate_app_commands_from_file_with_metadata(
    resolved_input,
  )
  @mbfs.write_string_to_file(resolved_output, result.source, encoding="utf8") catch {
    error =>
      raise CliCodegenOutputError::WriteFailed(
        path=resolved_output,
        detail=@debug.render(@debug.to_repr(error)),
      )
  }
  for warning in result.warnings {
    println("warning: " + warning)
  }
}

///|
async fn run_cli(cwd : String, matches : @argparse.Matches) -> Bool {
  match matches.subcommand {
    Some(("version", _)) => println(cli_version_text())
    Some(("doctor", doctor_matches)) => return run_doctor(cwd, doctor_matches)
    Some(("new", new_matches)) => @new_project.run(cwd, new_matches)
    Some(("dev", dev_matches)) => @dev.run(cwd, dev_matches)
    Some(("build", build_matches)) => @build.run(cwd, build_matches)
    Some(("package", package_matches)) => @package.run(cwd, package_matches)
    Some(("codegen", codegen_matches)) => run_codegen(cwd, codegen_matches)
    Some(("cef", cef_matches)) => @cef.run(cwd, cef_matches)
    _ => abort("argparse invariant violated: missing subcommand")
  }
  true
}

///|
fn exit_with_error(message : String) -> Bool {
  print_error_message(message)
  @sys.exit(1)
  false
}

///|
async fn main {
  let argv = @sys.get_cli_args()
  let raw_args = if argv.length() > 0 { argv[1:].to_owned() } else { [] }
  let matches = cli_command().parse(argv=raw_args, env=Map([])) catch {
    error => {
      let _ = exit_with_error(error.to_string())
      return
    }
  }
  let cwd = @cli_args.required_value(matches, "cwd")
  if matches.subcommand is Some(("version", _)) {
    println(cli_version_text())
    return
  }
  check_cli_update()
  let success = try run_cli(cwd, matches) catch {
    error => exit_with_error(error.to_string())
  } noraise {
    success => success
  }
  if !success {
    @sys.exit(1)
  }
}
