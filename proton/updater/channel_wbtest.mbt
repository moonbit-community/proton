///|
let trusted_key : String = "rsa-sha256:\{vector_modulus_hex}:010001"

///|
let manifest_url : String = "https://example.com/latest.json"

///|
let artifact_url : String = "https://example.com/App-0.3.0.zip"

///|
/// A network that serves exactly what is put into it.
///
/// Every test below is a statement about which bytes reach the client, so the
/// substitution being tested is always visible in the table rather than hidden
/// in a server.
fn serving(entries : Array[(String, Bytes)]) -> Fetch {
  fn(url) raise UpdateError {
    for entry in entries {
      if entry.0 == url {
        return entry.1
      }
    }
    raise FetchFailed(url~, detail="not served")
  }
}

///|
fn text_bytes(text : String) -> Bytes {
  let out : Array[Byte] = []
  for character in text {
    out.push(character.to_int().to_byte())
  }
  Bytes::from_array(out[:])
}

///|
fn default_entries() -> Array[(String, Bytes)] {
  [
    (manifest_url, text_bytes(vector_manifest)),
    ("\{manifest_url}.sig", text_bytes(vector_manifest_signature_hex)),
    (artifact_url, vector_artifact),
  ]
}

///|
fn channel(current : String) -> UpdateChannel raise {
  UpdateChannel::new(
    manifest_url,
    [trusted_key],
    "darwin-arm64",
    @manifest.Version::parse(current).unwrap(),
  )
}

///|
fn accepted_from() -> @manifest.Timestamp {
  @manifest.Timestamp::parse("2026-07-01T00:00:00Z").unwrap()
}

///|
async fn check_error(
  entries : Array[(String, Bytes)],
  current : String,
  oldest : @manifest.Timestamp,
) -> UpdateError {
  // The channel is built first so the catch below binds this package's error
  // type rather than whatever building it might raise.
  let channel = channel(current)
  let _ = channel.check(serving(entries), oldest) catch {
    error => return error
  }
  abort("expected the check to be refused")
}

///|
async test "authenticates a newer release end to end" {
  let outcome = channel("0.2.0").check(
    serving(default_entries()),
    accepted_from(),
  )
  guard outcome is Available(update) else {
    abort("expected an available update")
  }
  inspect(update.version(), content="0.3.0")
  assert_eq(update.notes_url(), Some("https://example.com/notes"))
  assert_eq(update.url(), artifact_url)
  assert_eq(update.size(), 11L)
  // The digest in the manifest is the one the artifact actually has, so the
  // download below is checking a real claim rather than a self-consistent one.
  assert_eq(update.sha256_hex, vector_artifact_sha256_hex)

  // The artifact is authenticated separately from the manifest that described
  // it, so a compromised host cannot substitute one for the other.
  let bytes = channel("0.2.0").download(serving(default_entries()), update)
  assert_eq(bytes.length(), 11)
}

///|
async test "offers nothing when the running version is not older" {
  assert_eq(
    channel("0.3.0").check(serving(default_entries()), accepted_from()),
    UpToDate,
  )
  // A replayed older release is the rollback the version rule exists to stop.
  assert_eq(
    channel("0.4.0").check(serving(default_entries()), accepted_from()),
    UpToDate,
  )
}

///|
async test "offers nothing for a platform the manifest does not name" {
  let other = UpdateChannel::new(
    manifest_url,
    [trusted_key],
    "win32-x64",
    @manifest.Version::parse("0.2.0").unwrap(),
  )
  assert_eq(other.check(serving(default_entries()), accepted_from()), UpToDate)
}

///|
async test "refuses a manifest that a trusted key did not sign" {
  // One flipped byte in the signature.
  let tampered = vector_manifest_signature_hex.replace(
    old=vector_manifest_signature_hex[0:2].to_owned(),
    new="00",
  )
  let entries = [
    (manifest_url, text_bytes(vector_manifest)),
    ("\{manifest_url}.sig", text_bytes(tampered)),
    (artifact_url, vector_artifact),
  ]
  assert_eq(
    check_error(entries, "0.2.0", accepted_from()),
    ManifestSignatureInvalid,
  )
}

///|
async test "refuses a manifest whose contents were altered after signing" {
  // The signature is authentic, but it covers different bytes. This is the
  // substitution the manifest signature exists to stop: the version and the
  // artifact digest are both inside what was signed.
  let altered = vector_manifest.replace(old="0.3.0", new="9.9.9")
  let entries = [
    (manifest_url, text_bytes(altered)),
    ("\{manifest_url}.sig", text_bytes(vector_manifest_signature_hex)),
  ]
  assert_eq(
    check_error(entries, "0.2.0", accepted_from()),
    ManifestSignatureInvalid,
  )
}

///|
async test "refuses a manifest older than the freshness window" {
  // Pinning a client to a stale manifest is how an attacker hides a fix. The
  // signature is valid here; the publication instant is what refuses it.
  let error = check_error(
    default_entries(),
    "0.2.0",
    @manifest.Timestamp::parse("2026-09-01T00:00:00Z").unwrap(),
  )
  assert_eq(
    error,
    ManifestStale(
      published_at="2026-08-01T00:00:00Z",
      oldest_accepted="2026-09-01T00:00:00Z",
    ),
  )
}

///|
async test "refuses when the manifest or its signature cannot be fetched" {
  assert_true(
    check_error(
      [(manifest_url, text_bytes(vector_manifest))],
      "0.2.0",
      accepted_from(),
    )
    is FetchFailed(_),
  )
  assert_true(check_error([], "0.2.0", accepted_from()) is FetchFailed(_))
}

///|
async test "refuses a signature that is not hexadecimal" {
  let entries = [
    (manifest_url, text_bytes(vector_manifest)),
    ("\{manifest_url}.sig", text_bytes("not a signature")),
  ]
  assert_true(
    check_error(entries, "0.2.0", accepted_from()) is MalformedSignature(_),
  )
  // A shell pipeline appends a newline; that must not be a failure.
  let padded = [
    (manifest_url, text_bytes(vector_manifest)),
    ("\{manifest_url}.sig", text_bytes("\{vector_manifest_signature_hex}\n")),
  ]
  assert_true(
    channel("0.2.0").check(serving(padded), accepted_from()) is Available(_),
  )
}

///|
async test "refuses an artifact whose bytes are not the ones described" {
  let outcome = channel("0.2.0").check(
    serving(default_entries()),
    accepted_from(),
  )
  guard outcome is Available(update) else {
    abort("expected an available update")
  }
  let download_error = async fn(body : String) -> UpdateError {
    let channel = channel("0.2.0")
    let entries : Array[(String, Bytes)] = [(artifact_url, text_bytes(body))]
    let _ = channel.download(serving(entries), update) catch {
      error => return error
    }
    abort("expected the artifact to be refused")
  }
  assert_true(download_error("short") is ArtifactSizeMismatch(_))
  // Right length, wrong content: the digest is what catches this one.
  assert_true(download_error("proton ZIP\n") is ArtifactDigestMismatch(_))
}

///|
async test "refuses a key that cannot be used" {
  let build = fn() -> UpdateError {
    let _ = UpdateChannel::new(
      manifest_url,
      ["rsa-sha256:00\{vector_modulus_hex}:010001"],
      "darwin-arm64",
      @manifest.Version::parse("0.2.0").unwrap(),
    ) catch {
      error => return error
    }
    abort("expected the key to be refused")
  }
  assert_true(build() is UntrustedKey(_))
}

///|
async test "accepts a signature from any trusted key, not only the first" {
  // A reserve key is distributed before it is used, so rotation does not need
  // a transition release. An unrelated key listed first must not prevent the
  // real signer from being recognised.
  let unrelated = "rsa-sha256:\{vector_modulus_hex.replace(old="94c0", new="94c1")}:010001"
  let rotated = UpdateChannel::new(
    manifest_url,
    [unrelated, trusted_key],
    "darwin-arm64",
    @manifest.Version::parse("0.2.0").unwrap(),
  )
  assert_true(
    rotated.check(serving(default_entries()), accepted_from()) is Available(_),
  )
}
