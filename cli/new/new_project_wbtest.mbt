///|
test "new delegates the default template without forcing a username" {
  let args = moon_new_arguments(command().parse(argv=[], env=Map([])))
  @debug.assert_eq(args, [
    "moonbit-community/moon-new@0.1.0", "todo", "--template", "moonbit-community/proton",
    "--branch", "main", "--subdir", "templates/isomorphic",
  ])
}

///|
test "explicit template and author are forwarded as literal arguments" {
  let args = moon_new_arguments(
    command().parse(
      argv=[
        "parent folder/demo", "--template", "minimal", "--author", "example",
      ],
      env=Map([]),
    ),
  )
  @debug.assert_eq(args, [
    "moonbit-community/moon-new@0.1.0", "parent folder/demo", "--template", "moonbit-community/proton",
    "--branch", "main", "--subdir", "templates/minimal", "--user", "example",
  ])
}

///|
test "unknown templates and removed options are rejected" {
  try
    moon_new_arguments(
      command().parse(argv=["--template", "todo"], env=Map([])),
    )
  catch {
    InvalidTemplate("todo") => ()
    _ => abort("expected invalid template")
  } noraise {
    _ => abort("expected invalid template")
  }
  for
    args in [
      ["--title", "Example"],
      ["--identifier", "com.example.app"],
      ["--width", "960"],
      ["--height", "640"],
      ["--check"],
      ["--no-check"],
      ["--git"],
      ["--no-git"],
      ["--dry-run"],
      ["--yes"],
      ["-y"],
    ] {
    try command().parse(argv=args, env=Map([])) catch {
      _ => ()
    } noraise {
      _ => abort("removed option accepted: " + args[0])
    }
  }
}
