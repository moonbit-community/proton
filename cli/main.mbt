///|
let cli_current_version : String = "0.1.14"

///|
let cli_manifest_url : String = "https://mooncakes.io/api/v0/manifest/moonbit-community/proton_cli"

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
  match @env.get_env_var("PROTON_NO_UPDATE_CHECK") {
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
async fn check_cli_update() -> Unit {
  guard !cli_update_check_disabled() else { return }
  match fetch_latest_cli_version() {
    Some(latest) =>
      if cli_version_is_newer(latest, cli_current_version) {
        @output.write_stderr_line(
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
async fn print_error_message(message : String) -> Unit {
  if message.has_prefix("error: ") {
    @output.write_stderr_line(message)
  } else {
    @output.write_stderr_line("error: " + message)
  }
}

///|
fn codegen_command() -> @argparse.Command {
  @argparse.Command(
    "codegen",
    about="Generate typed Proton command registrars from #proton attributes",
    flags=[
      FlagArg(
        "extension-identity",
        about="Generate a contract identity from one moon.ext input",
      ),
    ],
    options=[
      OptionArg(
        "output-file",
        short='o',
        about="Output .g.mbt file",
        required=true,
      ),
      OptionArg(
        "identity-name",
        about="Generated binding name for --extension-identity",
      ),
    ],
    positionals=[
      PositionArg(
        "input_files",
        about="Input MoonBit source files",
        num_args=@argparse.ValueRange(lower=1),
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
      @updater.command(),
    ],
    arg_required_else_help=true,
    subcommand_required=true,
  )
}

///|
async fn run_doctor(cwd : String, matches : @argparse.Matches) -> Bool {
  guard matches.flags
    is {
      "dry-run"? : Some(dry_run)
      | (None with dry_run = false),
      "verbose"? : Some(verbose)
      | (None with verbose = false),
      "deep"? : Some(deep)
      | (None with deep = false),
      "run"? : Some(run_frontend)
      | (None with run_frontend = false),
      "fix"? : Some(fix)
      | (None with fix = false),
      "json"? : Some(json)
      | (None with json = false),
      "json-lines"? : Some(json_lines)
      | (None with json_lines = false),
      "quiet"? : Some(quiet)
      | (None with quiet = false),
      "frontend"? : Some(frontend)
      | (None with frontend = false),
      "release"? : Some(release)
      | (None with release = false),
      ..
    }
  guard matches.values
    is {
      "section"? : Some(section_args)
      | (None with section_args = []),
      "output"? : Some(output_args)
      | (None with output_args = []),
      ..
    }
  let sections = section_args.copy()
  if frontend && !sections.contains("frontend") {
    sections.push("frontend")
  }
  if release && !sections.contains("release") {
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
  let output = match output_args {
    [path, ..] => Some(@fsutil.resolve_path(cwd, path))
    [] => None
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
async fn run_codegen(cwd : String, matches : @argparse.Matches) -> Unit {
  guard! matches.values
    is {
      "input_files"? : Some(inputs)
      | (None with inputs = []),
      "output-file": [output, ..],
      "identity-name"? : Some(identity_args)
      | (None with identity_args = []),
      ..
    }
  guard matches.flags
    is {
      "extension-identity"? : Some(extension_identity)
      | (None with extension_identity = false),
      ..
    }
  let resolved_inputs = inputs.map(input => @fsutil.resolve_path(cwd, input))
  let resolved_output = @fsutil.resolve_path(cwd, output)
  let identity_name = identity_args.get(0)
  if !extension_identity && identity_name is Some(_) {
    raise CliUsageError::Invalid(
      message="codegen --identity-name requires --extension-identity",
    )
  }
  let result = if extension_identity {
    guard resolved_inputs is [metadata_path] else {
      raise CliUsageError::Invalid(
        message="codegen --extension-identity requires exactly one moon.ext input",
      )
    }
    @codegen.generate_extension_identity_from_file(
      metadata_path,
      binding_name=identity_name.unwrap_or("generated_extension_contract"),
    )
  } else {
    @codegen.generate_commands_from_files(resolved_inputs)
  }
  @async_fs.write_file(
    resolved_output,
    result.source,
    create_mode=CreateOrTruncate,
  ) catch {
    error =>
      raise CliCodegenOutputError::WriteFailed(
        path=resolved_output,
        detail=@debug.render(Repr(error)),
      )
  }
  println("wrote " + resolved_output)
  for warning in result.warnings {
    @output.write_stderr_line("warning: " + warning)
  }
}

///|
async fn dispatch_cli(cwd : String, matches : @argparse.Matches) -> Bool {
  match matches.subcommand {
    Some(("version", _)) => println(cli_version_text())
    Some(("doctor", doctor_matches)) => return run_doctor(cwd, doctor_matches)
    Some(("new", new_matches)) => @new_project.run(cwd, new_matches)
    Some(("dev", dev_matches)) => @dev.run(cwd, dev_matches)
    Some(("build", build_matches)) => @build.run(cwd, build_matches)
    Some(("package", package_matches)) => @package.run(cwd, package_matches)
    Some(("codegen", codegen_matches)) => run_codegen(cwd, codegen_matches)
    Some(("cef", cef_matches)) => @cef.run(cwd, cef_matches)
    Some(("updater", updater_matches)) => @updater.run(updater_matches)
    _ => abort("argparse invariant violated: missing subcommand")
  }
  true
}

///|
async fn run(args : ArrayView[String]) -> Int {
  let matches = @argparse.parse(cli_command(), argv=args, env=Map([])) catch {
    error => {
      print_error_message(error.to_string())
      return 2
    }
  }
  guard! matches.values is { "cwd": [cwd, ..], .. }
  if !(matches.subcommand is Some(("version", _))) {
    check_cli_update()
  }
  try dispatch_cli(cwd, matches) catch {
    error => {
      print_error_message(error.to_string())
      1
    }
  } noraise {
    success => if success { 0 } else { 1 }
  }
}

///|
async fn main {
  let code = run(@env.args()[1:])
  if code != 0 {
    @sys.exit(code)
  }
}
