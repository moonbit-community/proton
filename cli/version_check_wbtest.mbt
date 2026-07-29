///|
test "update check env flag accepts common truthy and falsey values" {
  assert_true(env_flag_is_enabled("1"))
  assert_true(env_flag_is_enabled("true"))
  assert_true(env_flag_is_enabled(" yes "))
  assert_true(!env_flag_is_enabled(""))
  assert_true(!env_flag_is_enabled("0"))
  assert_true(!env_flag_is_enabled("false"))
  assert_true(!env_flag_is_enabled("off"))
}

///|
test "parse cli semver versions" {
  match parse_cli_version("1.2.3") {
    Some(version) => {
      assert_eq(version.major, 1)
      assert_eq(version.minor, 2)
      assert_eq(version.patch, 3)
    }
    None => fail("expected version to parse")
  }
  match parse_cli_version("1.2.3-beta.1") {
    Some(version) => {
      assert_eq(version.major, 1)
      assert_eq(version.minor, 2)
      assert_eq(version.patch, 3)
    }
    None => fail("expected prerelease version to parse")
  }
  assert_true(parse_cli_version("1.2") is None)
  assert_true(parse_cli_version("1.two.3") is None)
}

///|
test "cli version comparison detects newer releases" {
  assert_true(cli_version_is_newer("0.1.6", "0.1.5"))
  assert_true(cli_version_is_newer("0.2.0", "0.1.9"))
  assert_true(cli_version_is_newer("1.0.0", "0.9.9"))
  assert_true(!cli_version_is_newer("0.1.5", "0.1.5"))
  assert_true(!cli_version_is_newer("0.1.4", "0.1.5"))
  assert_true(!cli_version_is_newer("latest", "0.1.5"))
}

///|
test "latest version is read from mooncakes manifest" {
  let text =
    #|{"name":"justjavac/proton_cli","latest_version":"0.1.6","versions":[]}
  match latest_version_from_manifest_text(text) {
    Some(version) => assert_eq(version, "0.1.6")
    None => fail("expected latest_version")
  }
  assert_true(latest_version_from_manifest_text("{}") is None)
  assert_true(latest_version_from_manifest_text("not json") is None)
}

///|
test "cli version command text and subcommand" {
  assert_eq(cli_version_text(), "proton_cli " + cli_current_version)
  let matches = cli_command().parse(argv=["version"], env=Map([]))
  assert_true(matches.subcommand is Some(("version", _)))
}

///|
test "global cwd is inherited and separator protects app arguments" {
  let matches = cli_command().parse(
    argv=["-C", "repo", "dev", "--package", "app", "--", "-C", "app-cwd"],
    env=Map([]),
  )
  @debug.assert_eq(matches.values.get("cwd"), Some(["repo"]))
  match matches.subcommand {
    Some(("dev", dev_matches)) => {
      @debug.assert_eq(dev_matches.values.get("cwd"), Some(["repo"]))
      @debug.assert_eq(
        dev_matches.values.get("app-args"),
        Some(["-C", "app-cwd"]),
      )
    }
    _ => fail("expected dev subcommand")
  }
}

///|
test "global cwd can be supplied after subcommand" {
  let matches = cli_command().parse(
    argv=["dev", "--cwd", "repo", "--package", "app"],
    env=Map([]),
  )
  @debug.assert_eq(matches.values.get("cwd"), Some(["repo"]))
}

///|
test "doctor output modes are declaratively exclusive" {
  try
    cli_command().parse(argv=["doctor", "--json", "--quiet"], env=Map([]))
  catch {
    error =>
      assert_true(
        error.to_string().contains("conflicting arguments: json and quiet"),
      )
  } noraise {
    _ => fail("expected argparse to reject conflicting output modes")
  }
}

///|
fn moon_mod_version_from_source(path : String, source : String) -> String? {
  let (ast, reports) = @moon_config.parse_moon_mod(name=path, source)
  guard reports.length() == 0 else { return None }
  match ast {
    @moon_config.Ast::Obj(fields, ..) => {
      for field in fields {
        match field {
          ("version", @moon_config.Ast::Str(version, ..)) =>
            return Some(version)
          _ => ()
        }
      }
      None
    }
    _ => None
  }
}

///|
test "embedded cli version matches moon.mod" {
  let path = "moon.mod"
  let source = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    err =>
      fail("failed to read " + path + ": " + @debug.render(@debug.to_repr(err)))
  }
  match moon_mod_version_from_source(path, source) {
    Some(version) => assert_eq(cli_current_version, version)
    None => fail("expected moon.mod version to parse")
  }
}
