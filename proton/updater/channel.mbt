///|
/// Fetches the whole body at a URL.
///
/// The network is a parameter rather than a dependency so that the sequence
/// below — verify, decode, compare, verify again — can be exercised end to end
/// without one. That sequence is the part worth testing exhaustively; an HTTP
/// client is not.
pub type Fetch = async (String) -> Bytes raise UpdateError

///|
/// An update channel, resolved from configuration.
pub struct UpdateChannel {
  endpoint : String
  trusted_keys : Array[@rsa.PublicKey]
  platform : String
  current_version : @manifest.Version
}

///|
/// Resolves a channel from its configured form.
///
/// Trusted keys are parsed once, here, so that a key which cannot be used is
/// reported when the channel is built rather than at the moment a signature
/// needs checking.
pub fn UpdateChannel::new(
  endpoint : String,
  public_keys : Array[String],
  platform : String,
  current_version : @manifest.Version,
) -> UpdateChannel raise UpdateError {
  let trusted_keys : Array[@rsa.PublicKey] = []
  for text in public_keys {
    let key = @rsa.PublicKey::parse(text) catch {
      error => raise UntrustedKey(detail=error.message())
    }
    trusted_keys.push(key)
  }
  UpdateChannel::{ endpoint, trusted_keys, platform, current_version }
}

///|
/// What a check concluded.
pub enum CheckOutcome {
  /// Nothing newer is on offer for this platform.
  UpToDate
  /// A newer release is available and has been fully authenticated.
  Available(AvailableUpdate)
} derive(Eq, Debug)

///|
/// A release that passed every check short of being downloaded.
pub struct AvailableUpdate {
  version : @manifest.Version
  notes_url : String?
  url : String
  size : Int64
  sha256_hex : String
  signature_hex : String
} derive(Eq, Debug)

///|
pub fn AvailableUpdate::version(self : AvailableUpdate) -> @manifest.Version {
  self.version
}

///|
pub fn AvailableUpdate::notes_url(self : AvailableUpdate) -> String? {
  self.notes_url
}

///|
pub fn AvailableUpdate::url(self : AvailableUpdate) -> String {
  self.url
}

///|
pub fn AvailableUpdate::size(self : AvailableUpdate) -> Int64 {
  self.size
}

///|
/// Checks the channel for a newer release.
///
/// `oldest_accepted` is the earliest publication instant this client will
/// believe. It is supplied rather than derived from a clock inside this
/// function: the calendar arithmetic that turns a freshness window into an
/// instant belongs where a date library is available, and keeping it out means
/// the whole check can be tested by naming the instant directly.
///
/// The order of the steps is the point. The signature is checked before the
/// document is parsed, so no attacker-supplied structure is interpreted until
/// it is known to come from a trusted key. Freshness and version are checked
/// after, because both read fields that only the signature makes trustworthy.
pub async fn UpdateChannel::check(
  self : UpdateChannel,
  fetch : Fetch,
  oldest_accepted : @manifest.Timestamp,
) -> CheckOutcome raise UpdateError {
  let document = fetch(self.endpoint)
  let signature_url = "\{self.endpoint}.sig"
  let signature = decode_hex_body(fetch(signature_url), signature_url)
  guard self.verifies(sha256_of(document), signature) else {
    raise ManifestSignatureInvalid
  }
  let text = bytes_to_utf8(document)
  let manifest = @manifest.Manifest::parse(text) catch {
    error => raise ManifestUndecodable(detail=error.message())
  }
  let published_at = manifest.published_at()
  guard !published_at.is_before(oldest_accepted) else {
    raise ManifestStale(
      published_at=published_at.to_text(),
      oldest_accepted=oldest_accepted.to_text(),
    )
  }
  guard manifest.version().is_newer_than(self.current_version) else {
    return UpToDate
  }
  match manifest.platform(self.platform) {
    None => UpToDate
    Some(update) =>
      Available(AvailableUpdate::{
        version: manifest.version(),
        notes_url: manifest.notes_url(),
        url: update.url(),
        size: update.size(),
        sha256_hex: update.sha256_hex(),
        signature_hex: update.signature_hex(),
      })
  }
}

///|
/// Fetches an available update and authenticates the bytes received.
///
/// The declared size and digest are checked before the signature, because both
/// are cheap and a mismatch means the transfer was wrong regardless of who
/// signed what. The signature is what makes the result trustworthy; the digest
/// only makes the failure easier to describe.
pub async fn UpdateChannel::download(
  self : UpdateChannel,
  fetch : Fetch,
  update : AvailableUpdate,
) -> Bytes raise UpdateError {
  let artifact = fetch(update.url)
  let actual_size = artifact.length().to_int64()
  guard actual_size == update.size else {
    raise ArtifactSizeMismatch(expected=update.size, actual=actual_size)
  }
  let digest = sha256_of(artifact)
  let actual_digest = @crypto.bytes_to_hex_string(digest)
  guard actual_digest == update.sha256_hex else {
    raise ArtifactDigestMismatch(
      expected=update.sha256_hex,
      actual=actual_digest,
    )
  }
  let signature = decode_hex_body_text(update.signature_hex, update.url)
  guard self.verifies(digest, signature) else { raise ArtifactSignatureInvalid }
  artifact
}

///|
/// Reports whether any trusted key signed this digest.
///
/// Every key is tried. A reserve key distributed before it is used is what
/// makes rotation possible without a transition release, so a signature from
/// any configured key is as good as a signature from the first.
fn UpdateChannel::verifies(
  self : UpdateChannel,
  digest : Bytes,
  signature : Bytes,
) -> Bool {
  for key in self.trusted_keys {
    if @rsa.verify_pkcs1_sha256(key, digest, signature) {
      return true
    }
  }
  false
}

///|
fn sha256_of(data : Bytes) -> Bytes {
  let hasher = @crypto.SHA256::new()
  hasher.update(data)
  let digest = hasher.finalize()
  Bytes::from_array(digest.iter().collect()[:])
}
