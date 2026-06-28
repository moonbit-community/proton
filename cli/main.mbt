///|
fn print_usage() -> Unit {
  let usage =
    #|Usage:
    #|  proton_cli [-C DIR] doctor [--dry-run] [--verbose] [--json]
    #|  proton_cli codegen <input.mbt> -o <output.g.mbt>
    #|  proton_cli cef setup [--name <cef_binary_name>] [--url <url>]
    #|
  println(usage)
}

///|
priv enum CliError {
  UsageError(String, Bool)
  CommandError(String)
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
      }
    } else {
      rest.push(args[index])
      index = index + 1
    }
  }
  (cwd, rest)
}

///|
async fn run_doctor_from_args(
  cwd : String,
  args : Array[String],
) -> Result[Unit, CliError] {
  let mut dry_run = false
  let mut verbose = false
  let mut json = false
  for arg in args {
    match arg {
      "--dry-run" => dry_run = true
      "--verbose" => verbose = true
      "--json" => json = true
      "-h" | "--help" => {
        println(
          "Usage: proton_cli [-C DIR] doctor [--dry-run] [--verbose] [--json]",
        )
        return Ok(())
      }
      _ =>
        return Err(CliError::UsageError("unknown doctor option: " + arg, false))
    }
  }
  @doctor.run(cwd~, dry_run~, verbose~, json~).map_err(fn(message) {
    CliError::CommandError(message)
  })
}

///|
fn run_codegen(args : Array[String]) -> Result[Unit, CliError] {
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
  match @codegen.generate_app_commands_from_file_with_metadata(input) {
    Err(error) => Err(CliError::CommandError(error))
    Ok(result) => {
      @mbfs.write_string_to_file(output, result.source, encoding="utf8") catch {
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
  if args.length() == 0 || args[0] == "-h" || args[0] == "--help" {
    print_usage()
    return
  }
  let result = if args.length() >= 1 && args[0] == "doctor" {
    run_doctor_from_args(cwd, args[1:].to_owned())
  } else if args.length() >= 1 && args[0] == "codegen" {
    run_codegen(args[1:].to_owned())
  } else if args.length() >= 2 && args[0] == "cef" && args[1] == "setup" {
    run_cef_setup(cwd, args[2:].to_owned())
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
  }
}
