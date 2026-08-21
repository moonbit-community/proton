///|
let sample_sha256 : String = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

///|
fn manifest_json(platforms : String) -> String {
  (
    $|{"schema_version":2,"version":"0.2.0","revision":2,
    $| "published_at":"2026-08-01T00:00:00Z",
    $| "platforms":\{platforms}}
  )
}

///|
fn platform_json(overrides : String) -> String {
  (
    $|{"darwin-arm64":{"kind":"full",
    $| "url":"https://example.com/app.zip","size":1024,
    $| "sha256":"\{sample_sha256}","signature":"abcd"\{overrides}}}
  )
}

///|
fn parse_failure(text : String) -> ManifestError {
  let _ = Manifest::parse(text) catch { error => return error }
  abort("expected the manifest to be rejected")
}

///|
test "decodes a well formed manifest" {
  let manifest = Manifest::parse(manifest_json(platform_json("")))
  inspect(manifest.version(), content="0.2.0")
  assert_eq(manifest.revision(), 2UL)
  inspect(manifest.published_at(), content="2026-08-01T00:00:00Z")
  assert_eq(manifest.notes_url(), None)
  assert_eq(manifest.platforms(), ["darwin-arm64"])
  let update = manifest.platform("darwin-arm64").unwrap()
  assert_eq(update.url(), "https://example.com/app.zip")
  assert_eq(update.size(), 1024L)
  assert_eq(update.sha256_hex(), sample_sha256)
  assert_eq(update.signature_hex(), "abcd")
  assert_eq(manifest.platform("win32-x64"), None)
}

///|
test "rejects a document that is not a JSON object" {
  assert_eq(parse_failure("not json"), NotJson)
  assert_eq(parse_failure("[]"), NotAnObject(path="manifest"))
}

///|
test "rejects a schema version it does not implement" {
  let text = manifest_json(platform_json("")).replace(
    old="\"schema_version\":2",
    new="\"schema_version\":3",
  )
  assert_eq(parse_failure(text), UnknownSchemaVersion(found=3))
}

///|
test "rejects unknown fields rather than ignoring them" {
  let top = manifest_json(platform_json("")).replace(
    old="\"schema_version\":2",
    new="\"schema_version\":2,\"channel\":\"beta\"",
  )
  assert_eq(parse_failure(top), UnknownField(path="manifest.channel"))
  let nested = manifest_json(platform_json(",\"minimum_os\":\"12.0\""))
  assert_eq(
    parse_failure(nested),
    UnknownField(path="manifest.platforms.darwin-arm64.minimum_os"),
  )
}

///|
test "reports a missing required field by path" {
  let text = manifest_json(platform_json("")).replace(
    old="\"version\":\"0.2.0\",",
    new="",
  )
  assert_eq(parse_failure(text), MissingField(path="manifest.version"))
  let without_revision = manifest_json(platform_json("")).replace(
    old="\"revision\":2,",
    new="",
  )
  assert_eq(
    parse_failure(without_revision),
    MissingField(path="manifest.revision"),
  )
  assert_eq(
    parse_failure(
      (
        $|{"schema_version":2,"version":"0.2.0","revision":2,
        $| "published_at":"2026-08-01T00:00:00Z"}
      ),
    ),
    MissingField(path="manifest.platforms"),
  )
}

///|
test "rejects an invalid release revision" {
  let replace_revision = fn(value : String) {
    manifest_json(platform_json("")).replace(
      old="\"revision\":2",
      new="\"revision\":\{value}",
    )
  }
  assert_true(parse_failure(replace_revision("0")) is InvalidField(_))
  assert_true(parse_failure(replace_revision("-1")) is InvalidField(_))
  assert_true(parse_failure(replace_revision("1.5")) is InvalidField(_))
  assert_true(parse_failure(replace_revision("\"2\"")) is InvalidField(_))
  assert_eq(
    Manifest::parse(replace_revision("18446744073709551615")).revision(),
    18446744073709551615UL,
  )
}

///|
test "rejects an unimplemented artifact kind" {
  let text = manifest_json(
    (
      $|{"darwin-arm64":{"kind":"delta","url":"https://example.com/app.patch",
      $| "size":16,"sha256":"\{sample_sha256}","signature":"abcd"}}
    ),
  )
  assert_eq(
    parse_failure(text),
    InvalidField(
      path="manifest.platforms.darwin-arm64.kind",
      expectation="must be \"full\"",
    ),
  )
}

///|
test "rejects a platform entry whose fields are malformed" {
  let with_url = fn(url : String) {
    manifest_json(
      (
        $|{"darwin-arm64":{"kind":"full","url":"\{url}","size":1024,
        $| "sha256":"\{sample_sha256}","signature":"abcd"}}
      ),
    )
  }
  // Plain HTTP would let a network attacker choose the bytes; the signature
  // would still be checked, but there is no reason to offer the opportunity.
  assert_eq(
    parse_failure(with_url("http://example.com/app.zip")),
    InvalidField(
      path="manifest.platforms.darwin-arm64.url",
      expectation="must be an https URL",
    ),
  )
  let with_size = fn(size : String) {
    manifest_json(
      (
        $|{"darwin-arm64":{"kind":"full","url":"https://example.com/app.zip",
        $| "size":\{size},"sha256":"\{sample_sha256}","signature":"abcd"}}
      ),
    )
  }
  assert_true(parse_failure(with_size("0")) is InvalidField(_))
  assert_true(parse_failure(with_size("-1")) is InvalidField(_))
  assert_true(parse_failure(with_size("1.5")) is InvalidField(_))
  assert_true(parse_failure(with_size("\"1024\"")) is InvalidField(_))
}

///|
test "rejects digests and signatures that are not strict hexadecimal" {
  let with_digest = fn(digest : String) {
    manifest_json(
      (
        $|{"darwin-arm64":{"kind":"full","url":"https://example.com/app.zip",
        $| "size":1024,"sha256":"\{digest}","signature":"abcd"}}
      ),
    )
  }
  // Too short, uppercase, and a non-hexadecimal character.
  assert_true(parse_failure(with_digest("9f86d081")) is InvalidField(_))
  assert_true(
    parse_failure(with_digest(sample_sha256.to_upper())) is InvalidField(_),
  )
  assert_true(
    parse_failure(with_digest("z" + sample_sha256[1:].to_owned()))
    is InvalidField(_),
  )
  let with_signature = fn(signature : String) {
    manifest_json(
      (
        $|{"darwin-arm64":{"kind":"full","url":"https://example.com/app.zip",
        $| "size":1024,"sha256":"\{sample_sha256}","signature":"\{signature}"}}
      ),
    )
  }
  assert_true(parse_failure(with_signature("abc")) is InvalidField(_))
  assert_true(parse_failure(with_signature("")) is InvalidField(_))
  assert_true(parse_failure(with_signature("ab cd")) is InvalidField(_))
}

///|
test "accepts an optional notes url and rejects a non-string one" {
  let text = manifest_json(platform_json("")).replace(
    old="\"platforms\":",
    new="\"notes_url\":\"https://example.com/notes\",\"platforms\":",
  )
  assert_eq(
    Manifest::parse(text).notes_url(),
    Some("https://example.com/notes"),
  )
  let bad = manifest_json(platform_json("")).replace(
    old="\"platforms\":",
    new="\"notes_url\":7,\"platforms\":",
  )
  assert_true(parse_failure(bad) is InvalidField(_))
}
