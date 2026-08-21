///|
/// Returns the declarative `proton_cli cef` command specification.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "cef",
    about="Manage the Proton CEF installation",
    subcommands=[setup_command(), requirements_command()],
    subcommand_required=true,
  )
}

///|
fn setup_command() -> @argparse.Command {
  @argparse.Command(
    "setup",
    about="Install the shared Proton CEF runtime and subprocess helper",
  )
}

///|
fn requirements_command() -> @argparse.Command {
  @argparse.Command(
    "requirements",
    about="Print the CEF requirement embedded in this Proton release",
  )
}

///|
/// Runs a parsed CEF management subcommand.
pub async fn run(matches : @argparse.Matches) -> Unit {
  match matches.subcommand {
    Some(("setup", setup_matches)) => {
      ignore(setup_matches)
      let runtime = @cef_store.setup_default()
      println(runtime.runtime_root())
    }
    Some(("requirements", requirement_matches)) => {
      ignore(requirement_matches)
      println(@cef_store.default_requirement_json())
    }
    _ => abort("argparse invariant violated: missing cef subcommand")
  }
}
