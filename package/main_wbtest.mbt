///|
test "configuration decoding uses typed defaults" {
  let config = decode_package_config("{\"schema_version\":1}", "test.json")
  assert_eq(config.formats, None)
  assert_eq(config.sign, None)
  assert_eq(config.nsis_install_mode, None)
}

///|
async test "standalone NSIS configuration and command-line modes are accepted" {
  let required_args = [
    "--executable", "probe.exe", "--product-name", "Probe", "--identifier", "dev.proton.probe",
    "--version", "1.0.0",
  ]
  let default_spec = package_spec(command().parse(argv=required_args, env={}))
  assert_eq(
    default_spec.nsis_install_mode,
    @package.NsisInstallMode::CurrentUser,
  )
  let args = required_args.copy()
  args.append(["--nsis-install-mode", "perMachine"])
  let spec = package_spec(command().parse(argv=args, env={}))
  assert_eq(spec.nsis_install_mode, @package.NsisInstallMode::PerMachine)
  let config = decode_package_config(
    "{\"schema_version\":1,\"nsis_install_mode\":\"both\"}", "test.json",
  )
  assert_eq(config.nsis_install_mode, Some("both"))
}

///|
test "invalid configuration is a regular error" {
  try
    ignore(
      decode_package_config(
        "{\"schema_version\":1,\"payloads\":false}", "test.json",
      ),
    )
  catch {
    PackageCommandError::InvalidConfig(path~, ..) =>
      inspect(path, content="test.json")
    _ => fail("expected an invalid configuration error")
  } noraise {
    _ => fail("expected configuration decoding to fail")
  }
}

///|
test "missing merged options are regular errors" {
  try ignore(required(None, "executable")) catch {
    PackageCommandError::MissingOption(name~) =>
      inspect(name, content="executable")
    _ => fail("expected a missing option error")
  } noraise {
    _ => fail("expected required option validation to fail")
  }
}
