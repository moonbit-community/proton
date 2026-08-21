///|
fn command() -> @argparse.Command {
  @argparse.Command(
    "proton_cefsetup",
    about="Install the CEF runtime required by Proton",
  )
}

///|
async fn run(args : ArrayView[String]) -> Int {
  let matches = @argparse.parse(command(), argv=args, env=Map([])) catch {
    error => {
      println("error: " + error.to_string())
      return 2
    }
  }
  ignore(matches)
  try @store.setup_default() catch {
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
