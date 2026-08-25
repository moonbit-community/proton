///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "proton_cefsetup",
    about="Install the CEF runtime and subprocess helper required by Proton",
    flags=[
      @argparse.FlagArg(
        "runtime-only",
        about="Install the CEF runtime without installing the Proton helper",
      ),
    ],
  )
}

///|
async fn run(args : ArrayView[String]) -> Int {
  let matches = @argparse.parse(command(), argv=args, env=Map([])) catch {
    error => {
      println(error.to_string())
      return 2
    }
  }
  let runtime_only = matches.flags.get("runtime-only") == Some(true)
  try @store.setup_default(runtime_only~) catch {
    error => {
      println("error: " + error.to_string())
      1
    }
  } noraise {
    runtime => {
      println(runtime.runtime_root())
      0
    }
  }
}

///|
async fn main {
  let code = run(@env.args()[1:])
  if code != 0 {
    @sys.exit(code)
  }
}
