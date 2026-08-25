///|
test "configuration decoding uses typed defaults" {
  let config = decode_package_config("{\"schema_version\":1}", "test.json")
  assert_eq(config.formats, None)
  assert_eq(config.sign, None)
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
