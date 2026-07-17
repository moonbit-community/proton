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
test "cli version command text and aliases" {
  assert_eq(cli_version_text(), "proton_cli " + cli_current_version)
  assert_true(is_cli_version_arg("version"))
  assert_true(is_cli_version_arg("--version"))
  assert_true(is_cli_version_arg("-V"))
  assert_true(!is_cli_version_arg("doctor"))
}

///|
test "global cwd parsing only consumes leading flags" {
  let (cwd, args) = parse_global_args([
    "-C", "repo", "dev", "app", "--", "-C", "app-cwd",
  ])
  assert_eq(cwd, "repo")
  @debug.assert_eq(args, ["dev", "app", "--", "-C", "app-cwd"])
}

///|
test "global cwd parsing preserves command arguments after subcommand" {
  let (cwd, args) = parse_global_args(["dev", "app", "--", "--cwd", "app-cwd"])
  assert_eq(cwd, ".")
  @debug.assert_eq(args, ["dev", "app", "--", "--cwd", "app-cwd"])
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
