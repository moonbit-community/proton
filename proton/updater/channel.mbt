///|
/// Fetches the whole body at a URL.
///
/// The network is a parameter rather than a dependency so that the sequence
/// below — verify, decode, compare, verify again — can be exercised end to end
/// without one. That sequence is the part worth testing exhaustively; an HTTP
/// client is not.
pub type Fetch = async (String) -> Bytes raise UpdateError

///|
/// Streams an artifact into a consumer without retaining the whole body.
///
/// The expected size is authenticated manifest data. A transport may use it to
/// reject a mismatching response header early; `UpdateChannel` independently
/// enforces it against the chunks actually delivered.
pub type ArtifactFetch = async (
  String,
  Int64,
  async (Bytes) -> Unit raise UpdateError,
) -> Unit raise UpdateError

///|
fn artifact_size_after_chunk(
  expected : Int64,
  received : Int64,
  chunk_size : Int64,
) -> Int64 raise UpdateError {
  guard chunk_size <= expected - received else {
    let actual = if received > 0x7fffffffffffffffL - chunk_size {
      0x7fffffffffffffffL
    } else {
      received + chunk_size
    }
    raise ArtifactSizeMismatch(expected~, actual~)
  }
  received + chunk_size
}

///|
/// An update channel, resolved from configuration.
pub struct UpdateChannel {
  endpoint : String
  trusted_keys : Array[@rsa.PublicKey]
  platform : String
  current_revision : UInt64
}

///|
/// Resolves a channel from its configured form.
///
/// Trusted keys are parsed once, here, so that a key which cannot be used is
/// reported when the channel is built rather than at the moment a signature
/// needs checking.
pub fn UpdateChannel::UpdateChannel(
  endpoint : String,
  public_keys : Array[String],
  platform : String,
  current_revision : UInt64,
) -> UpdateChannel raise UpdateError {
  let trusted_keys : Array[@rsa.PublicKey] = []
  for text in public_keys {
    let key = @rsa.PublicKey::parse(text) catch {
      error => raise UntrustedKey(detail=error.message())
    }
    trusted_keys.push(key)
  }
  UpdateChannel::{ endpoint, trusted_keys, platform, current_revision }
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
pub extend CheckOutcome with Eq::{not_equal, equal}

///|
pub extend CheckOutcome with Debug::{to_repr}

///|
/// A release that passed every check short of being downloaded.
pub struct AvailableUpdate {
  version : @manifest.Version
  revision : UInt64
  notes_url : String?
  url : String
  size : Int64
  sha256_hex : String
  signature_hex : String
} derive(Eq, Debug)

///|
pub extend AvailableUpdate with Eq::{not_equal, equal}

///|
pub extend AvailableUpdate with Debug::{to_repr}

///|
pub fn AvailableUpdate::version(self : AvailableUpdate) -> @manifest.Version {
  self.version
}

///|
pub fn AvailableUpdate::revision(self : AvailableUpdate) -> UInt64 {
  self.revision
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
/// it is known to come from a trusted key. Freshness and revision are checked
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
  guard manifest.revision() > self.current_revision else { return UpToDate }
  match manifest.platform(self.platform) {
    None => UpToDate
    Some(update) =>
      Available(AvailableUpdate::{
        version: manifest.version(),
        revision: manifest.revision(),
        notes_url: manifest.notes_url(),
        url: update.url(),
        size: update.size(),
        sha256_hex: update.sha256_hex(),
        signature_hex: update.signature_hex(),
      })
  }
}

///|
/// Streams an available update into a staging consumer and authenticates it.
///
/// No complete artifact buffer is built here. Each accepted chunk is counted,
/// hashed and passed to `consume`; an oversized stream is refused before its
/// first out-of-bounds chunk reaches staging. The caller must discard staging
/// when this function raises, because bytes are not trusted until it returns.
async fn UpdateChannel::download_into(
  self : UpdateChannel,
  fetch : ArtifactFetch,
  update : AvailableUpdate,
  consume : async (Bytes) -> Unit raise UpdateError,
  on_progress : async (Int64) -> Unit noraise,
) -> Unit raise UpdateError {
  let received = Ref(0L)
  let hasher = @crypto.SHA256::new()
  fetch(update.url, update.size, async fn(chunk) -> Unit raise UpdateError {
    let chunk_size = chunk.length().to_int64()
    let actual_size = artifact_size_after_chunk(
      update.size,
      received.val,
      chunk_size,
    )
    consume(chunk)
    hasher.update(chunk)
    received.val = actual_size
    on_progress(actual_size)
  })
  guard received.val == update.size else {
    raise ArtifactSizeMismatch(expected=update.size, actual=received.val)
  }
  let digest = Bytes::from_array(hasher.finalize().iter().collect()[:])
  let actual_digest = @crypto.bytes_to_hex_string(digest)
  guard actual_digest == update.sha256_hex else {
    raise ArtifactDigestMismatch(
      expected=update.sha256_hex,
      actual=actual_digest,
    )
  }
  let signature = decode_hex_body_text(update.signature_hex, update.url)
  guard self.verifies(digest, signature) else { raise ArtifactSignatureInvalid }
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
