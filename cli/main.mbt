///|
fn print_usage() -> Unit {
  let usage =
    #|Usage:
    #|  lepus codegen commands <input.mbt> -o <output.g.mbt> --id <manifest-id> --namespace <jsNamespace>
    #|
  println(usage)
}

///|
fn print_error(error : String) -> Unit {
  if error.has_prefix("error: ") {
    println(error)
  } else {
    println("error: " + error)
  }
  if !error.contains("Usage:") {
    print_usage()
  }
}

///|
fn codegen_commands_arg_parser() -> @argparse.Command {
  @argparse.Command(
    "lepus codegen commands",
    about="Generate Lepus command extension code from #lepus attributes",
    options=[
      OptionArg(
        "output-file",
        short='o',
        about="Output .g.mbt file",
        required=true,
      ),
      OptionArg("id", about="Manifest/catalog extension id", required=true),
      OptionArg("namespace", about="JavaScript namespace", required=true),
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
fn run_codegen_commands(args : Array[String]) -> Result[Unit, String] {
  let cmd = codegen_commands_arg_parser()
  let matches = cmd.parse(argv=args, env={}) catch {
    err => return Err(err.to_string())
  }
  let input = match match_value(matches, "input_file") {
    Some(input) => input
    None => return Err("missing input file")
  }
  let output = match match_value(matches, "output-file") {
    Some(output) => output
    None => return Err("missing -o <output.g.mbt>")
  }
  let extension_id = match match_value(matches, "id") {
    Some(id) => id
    None => return Err("missing --id <manifest-id>")
  }
  let js_namespace = match match_value(matches, "namespace") {
    Some(value) => value
    None => return Err("missing --namespace <jsNamespace>")
  }
  match
    @codegen.generate_app_commands_from_file(input, extension_id, js_namespace) {
    Err(error) => Err(error)
    Ok(result) => {
      @mbfs.write_string_to_file(output, result.source, encoding="utf8") catch {
        err => return Err(@debug.render(@debug.to_repr(err)))
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
  let result = if args.length() >= 2 &&
    args[0] == "codegen" &&
    args[1] == "commands" {
    run_codegen_commands(args[2:].to_owned())
  } else {
    Err("unknown command")
  }
  match result {
    Ok(_) => ()
    Err(error) => {
      print_error(error)
      @sys.exit(1)
    }
  }
}
