///|
fn command() -> @argparse.Command {
  let options = [
    @argparse.OptionArg("config", about="JSON package specification"),
    @argparse.OptionArg(
      "executable",
      about="Already-built application executable",
    ),
  ]
  options.append(@package_args.options())
  @argparse.Command(
    "proton_package",
    about="Package an already-built desktop executable",
    flags=@package_args.flags(),
    options~,
    arg_required_else_help=true,
  )
}

///|
async fn run(args : ArrayView[String]) -> Unit {
  let matches = command().parse(argv=args, env={})
  for artifact in @package.build(package_spec(matches)) {
    println(artifact)
  }
}

///|
async fn main {
  run(@env.args()[1:]) catch {
    error => {
      let message = error.to_string()
      println(
        if message.has_prefix("error: ") {
          message
        } else {
          "error: " + message
        },
      )
      @sys.exit(1)
    }
  }
}
