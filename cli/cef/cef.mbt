///|
/// Returns the declarative `proton_cli cef` command specification.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "cef",
    about="Manage the Proton CEF runtime",
    subcommands=[setup_command()],
    subcommand_required=true,
  )
}

///|
fn setup_command() -> @argparse.Command {
  @argparse.Command("setup", about="Install the shared Proton CEF runtime")
}

///|
/// Runs a parsed CEF management subcommand.
pub async fn run(cwd : String, matches : @argparse.Matches) -> Unit {
  guard matches.subcommand is Some(("setup", setup_matches)) else {
    abort("argparse invariant violated: missing cef subcommand")
  }
  ignore(setup_matches)
  let requirements = @build.resolve_project_runtime_requirements(cwd)
  let runtime = @cef_store.install_declared(requirements)
  println(runtime.runtime_root())
}
