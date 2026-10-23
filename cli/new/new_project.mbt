///|
/// Creates a project using moon-new and the templates on Proton's main branch.
pub async fn run(cwd : String, matches : @argparse.Matches) -> Unit {
  let args = moon_new_arguments(matches)
  let code = @process.run("moonx", args, cwd~)
  if code != 0 {
    raise NewProjectError::GeneratorFailed(code)
  }
}

///|
/// Returns the declarative `proton_cli new` command specification.
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "new",
    about="Create a Proton project using moon-new",
    options=[
      OptionArg(
        "template",
        long="template",
        about="Project template: minimal or isomorphic (default)",
      ),
      OptionArg(
        "author",
        long="author",
        about="MoonBit module author (moon-new --user)",
      ),
    ],
    positionals=[
      PositionArg(
        "path",
        about="Project directory (default: todo)",
        num_args=ValueRange(lower=0, upper=1),
      ),
    ],
  )
}

///|
fn moon_new_arguments(
  matches : @argparse.Matches,
) -> Array[String] raise NewProjectError {
  guard matches.values
    is {
      "path"? : Some(path)
      | (None with path = []),
      "template"? : Some(template)
      | (None with template = []),
      "author"? : Some(author)
      | (None with author = []),
      ..
    }
  let template = template.get(0).unwrap_or("isomorphic").to_lower()
  guard template == "minimal" || template == "isomorphic" else {
    raise InvalidTemplate(template)
  }
  let args = [
    "moonbit-community/moon-new@0.1.0",
    path.get(0).unwrap_or("todo"),
    "--template",
    "moonbit-community/proton",
    "--branch",
    "main",
    "--subdir",
    "templates/" + template,
  ]
  if author.get(0) is Some(author) {
    args.push("--user")
    args.push(author)
  }
  args
}
