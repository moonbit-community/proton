///|
test "renders a fragment the updater module accepts" {
  let fragment = updater_fragment_json(
    "darwin-arm64", "0.2.0", "2026-08-01T00:00:00Z", "https://example.com/releases/Draw.app.zip",
    234881024L, "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
  )
  // Emitting and decoding are implemented in different modules, so the shape
  // is asserted against the text rather than against the decoder here; the
  // decoder's own tests cover the schema.
  inspect(
    fragment,
    content=(
      $|{
      $|  "schema_version": 1,
      $|  "version": "0.2.0",
      $|  "published_at": "2026-08-01T00:00:00Z",
      $|  "platforms": {
      $|    "darwin-arm64": {
      $|      "kind": "full",
      $|      "url": "https://example.com/releases/Draw.app.zip",
      $|      "size": 234881024,
      $|      "sha256": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
      $|      "signature": ""
      $|    }
      $|  }
      $|}
      $|
    ),
  )
}

///|
test "leaves the signature empty because signing needs the private key" {
  let fragment = updater_fragment_json(
    "win32-x64",
    "1.0.0",
    "2026-08-01T00:00:00Z",
    "https://example.com/App.zip",
    1024L,
    "0".repeat(64),
  )
  assert_true(fragment.contains("\"signature\": \"\""))
}

///|
test "the emitted fragment decodes with the runtime parser" {
  // Emitting and decoding live in different modules, so a fragment that the
  // runtime cannot read is a realistic failure. Packaging checks it rather
  // than leaving it to be discovered at an installation.
  verify_fragment_decodes(
    updater_fragment_json(
      "darwin-arm64", "0.2.0", "2026-08-01T00:00:00Z", "https://example.com/releases/Draw.app.zip",
      234881024L, "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
    ),
  )
}

///|
fn decode_failure(fragment : String) -> UpdaterMetadataError {
  verify_fragment_decodes(fragment) catch {
    error => return error
  }
  abort("expected the fragment to be rejected")
}

///|
test "a malformed fragment is caught at package time" {
  let bad_version = updater_fragment_json(
    "darwin-arm64",
    "0.2",
    "2026-08-01T00:00:00Z",
    "https://example.com/app.zip",
    1024L,
    "0".repeat(64),
  )
  assert_true(decode_failure(bad_version) is UndecodableFragment(_))
  let bad_instant = updater_fragment_json(
    "darwin-arm64",
    "0.2.0",
    "2026-08-01 12:00:00",
    "https://example.com/app.zip",
    1024L,
    "0".repeat(64),
  )
  assert_true(decode_failure(bad_instant) is UndecodableFragment(_))
}
