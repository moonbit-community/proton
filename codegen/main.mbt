///|
priv suberror CodegenCliError {
  Invalid(message~ : String)
  WriteFailed(path~ : String, detail~ : String)
} derive(Debug)

///|
fn CodegenCliError::message(self : CodegenCliError) -> String {
  match self {
    Invalid(message~) => message
    WriteFailed(path~, detail~) =>
      "failed to write generated source " + path + ": " + detail
  }
}

///|
impl Show for CodegenCliError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
fn codegen_command() -> @argparse.Command {
  @argparse.Command(
    "proton_codegen",
    about="Generate typed Proton command registrars from #proton attributes",
    flags=[
      FlagArg(
        "extension-identity",
        about="Generate a contract identity from one proton.ext.json input",
      ),
    ],
    options=[
      OptionArg(
        "cwd",
        short='C',
        default_values=["."],
        about="Resolve input and output paths from this directory",
      ),
      OptionArg(
        "output-file",
        short='o',
        about="Output .g.mbt file",
        required=true,
      ),
      OptionArg(
        "identity-name",
        about="Generated binding name for --extension-identity",
        requires=["extension-identity"],
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
async fn write_stderr_line(message : String) -> Unit noraise {
  @stdio.stderr.write(message + "\n") catch {
    _ => ()
  }
}

///|
fn resolve_from(cwd : @path.Path, value : String) -> String {
  let path = @path.Path(value)
  if path.is_absolute() {
    path.resolve().to_string()
  } else {
    cwd.join(path).to_string()
  }
}

///|
async fn generate(matches : @argparse.Matches) -> Unit {
  guard! matches.values
    is {
      "cwd": [cwd, ..],
      "input_files": inputs,
      "output-file": [output, ..],
      "identity-name"? : Some(identity_args)
      | (None with identity_args = []),
      ..
    }
  let cwd = @path.Path(cwd).resolve()
  let inputs = inputs.map(input => resolve_from(cwd, input))
  let output = resolve_from(cwd, output)
  guard matches.flags
    is {
      "extension-identity"? : Some(extension_identity)
      | (None with extension_identity = false),
      ..
    }
  let identity_name = identity_args.get(0)
  let result = if extension_identity {
    guard inputs is [metadata_path] else {
      raise CodegenCliError::Invalid(
        message="--extension-identity requires exactly one proton.ext.json input",
      )
    }
    @codegen.generate_extension_identity_from_file(
      metadata_path,
      binding_name=identity_name.unwrap_or("generated_extension_contract"),
    )
  } else {
    @codegen.generate_commands_from_files(inputs)
  }
  @async_fs.write_file(output, result.source, create_mode=CreateOrTruncate) catch {
    error =>
      raise CodegenCliError::WriteFailed(
        path=output,
        detail=@debug.render(Repr(error)),
      )
  }
  for warning in result.warnings {
    write_stderr_line("warning: " + warning)
  }
}

///|
async fn run(args : ArrayView[String]) -> Int {
  let matches = @argparse.parse(codegen_command(), argv=args, env=Map([])) catch {
    error => {
      write_stderr_line(error.to_string())
      return 2
    }
  }
  try generate(matches) catch {
    error => {
      write_stderr_line("error: " + error.to_string())
      1
    }
  } noraise {
    _ => 0
  }
}

///|
async fn main {
  let code = run(@env.args()[1:])
  if code != 0 {
    @sys.exit(code)
  }
}
