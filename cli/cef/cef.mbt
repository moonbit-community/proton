///|
/// Returns the declarative `proton_cli cef` command specification.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "cef",
    about="Inspect the Proton CEF requirement",
    subcommands=[requirements_command()],
    subcommand_required=true,
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
    Some(("requirements", requirement_matches)) => {
      ignore(requirement_matches)
      println(@cef_store.default_requirement_json())
    }
    _ => abort("argparse invariant violated: missing cef subcommand")
  }
}
