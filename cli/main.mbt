///|
fn print_usage() -> Unit {
  let usage =
    #|Usage:
    #|  proton codegen <input.mbt> -o <output.g.mbt>
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
    "proton codegen",
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
fn main {
  let argv = @sys.get_cli_args()
  let args = if argv.length() > 0 { argv[1:].to_owned() } else { [] }
  if args.length() == 0 || args[0] == "-h" || args[0] == "--help" {
    print_usage()
    return
  }
  let result = if args.length() >= 1 && args[0] == "codegen" {
    run_codegen(args[1:].to_owned())
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
