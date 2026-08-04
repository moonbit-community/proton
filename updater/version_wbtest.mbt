///|
fn version(text : String) -> Version {
  match Version::parse(text) {
    Some(value) => value
    None => abort("expected \{text} to parse")
  }
}

///|
test "parses and renders a three part version" {
  inspect(version("0.2.0"), content="0.2.0")
  inspect(version("1.0.0"), content="1.0.0")
  inspect(version("10.20.30"), content="10.20.30")
  inspect(version("0.0.0"), content="0.0.0")
}

///|
test "rejects anything that is not exactly three plain numbers" {
  for
    text in [
      "1.2", "1.2.3.4", "1", "", "1.2.x", "v1.2.3", "1.2.3-rc.1", "1.2.3+build",
      "1..3", "1.2.", ".2.3", " 1.2.3", "1.2.3 ", "-1.2.3", "+1.2.3",
    ] {
    assert_eq(Version::parse(text), None)
  }
}

///|
test "rejects leading zeros so one release has one spelling" {
  assert_eq(Version::parse("01.2.3"), None)
  assert_eq(Version::parse("1.02.3"), None)
  assert_eq(Version::parse("1.2.03"), None)
  // A single zero is the one legitimate way to write zero.
  inspect(version("0.0.0"), content="0.0.0")
}

///|
test "rejects a component too large to represent" {
  assert_eq(Version::parse("99999999999.0.0"), None)
  inspect(version("2147483647.0.0"), content="2147483647.0.0")
}

///|
test "orders versions by major, then minor, then patch" {
  assert_true(version("1.0.0").is_newer_than(version("0.9.9")))
  assert_true(version("1.1.0").is_newer_than(version("1.0.9")))
  assert_true(version("1.0.1").is_newer_than(version("1.0.0")))
  assert_true(version("0.10.0").is_newer_than(version("0.9.0")))
  assert_true(version("0.2.10").is_newer_than(version("0.2.9")))
}

///|
test "treats an equal or older version as no update" {
  // This is the rollback control: only a strictly greater version is offered,
  // so replaying an older signed release cannot reintroduce a fixed defect.
  assert_false(version("1.0.0").is_newer_than(version("1.0.0")))
  assert_false(version("0.9.9").is_newer_than(version("1.0.0")))
  assert_false(version("1.0.0").is_newer_than(version("1.0.1")))
  assert_false(version("1.0.0").is_newer_than(version("1.1.0")))
  assert_false(version("0.9.0").is_newer_than(version("0.10.0")))
}
