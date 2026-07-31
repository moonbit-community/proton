///|
/// An update manifest fragment could not be produced.
pub(all) suberror UpdaterMetadataError {
  NoDistributableArtifact
  UnreadableArtifact(path~ : String, detail~ : String)
  InvalidBaseUrl(url~ : String)
  UnknownPlatform(detail~ : String)
  MissingPublishedAt
  UndecodableFragment(detail~ : String)
} derive(Eq)

///|
pub fn UpdaterMetadataError::message(self : UpdaterMetadataError) -> String {
  match self {
    NoDistributableArtifact =>
      (
        $|no distributable artifact to describe
        $|
        $|An update is downloaded as a single file, so the manifest fragment
        $|needs a zip or dmg target. A bare .app directory cannot be fetched.
      )
    UnreadableArtifact(path~, detail~) => "cannot read \{path}: \{detail}"
    InvalidBaseUrl(url~) => "updater base URL must begin with https://: \{url}"
    UnknownPlatform(detail~) => "cannot determine the host platform: \{detail}"
    MissingPublishedAt =>
      (
        $|--updater-published-at is required with --updater-base-url
        $|
        $|The instant is supplied rather than read from the clock so that a
        $|release is reproducible. Use UTC, to the second:
        $|
        $|  --updater-published-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      )
    UndecodableFragment(detail~) =>
      "the emitted manifest fragment does not decode: \{detail}"
  }
}

///|
impl Show for UpdaterMetadataError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
/// Returns the SHA-256 and byte length of a file, from one pass over it.
///
/// A packaged application reaches hundreds of megabytes, so the digest is
/// accumulated a megabyte at a time rather than the file being read into
/// memory. The length is counted from the same pass, so the two values cannot
/// describe different states of the file.
async fn artifact_digest_and_size(
  path : String,
) -> (String, Int64) raise UpdaterMetadataError {
  let file = @async_fs.open(path, mode=ReadOnly) catch {
    error => raise UnreadableArtifact(path~, detail=@debug.render(Repr(error)))
  }
  defer file.close()
  let hasher = @crypto.SHA256::new()
  let buffer = FixedArray::make(1024 * 1024, b'\x00')
  let mut size = 0L
  for ;; {
    let read = file.read(buffer) catch {
      error =>
        raise UnreadableArtifact(path~, detail=@debug.render(Repr(error)))
    }
    if read <= 0 {
      break
    }
    hasher.update(buffer.unsafe_reinterpret_as_bytes()[:read])
    size = size + read.to_int64()
  }
  (@crypto.bytes_to_hex_string(hasher.finalize()), size)
}

///|
/// Returns the artifact an update would download.
///
/// A zip is preferred over a dmg because it is the smaller of the two and
/// needs no mounting to expand. The `.app` directory is never a candidate: it
/// is a directory, and an update is fetched as one file.
fn updater_artifact_path(plan : PackagePlan) -> String? {
  if plan.targets.contains("zip") {
    return Some(macos_zip_path(plan))
  }
  if plan.targets.contains("dmg") {
    return Some(macos_dmg_path(plan))
  }
  None
}

///|
/// Builds the manifest fragment for the platform that was just packaged.
///
/// The `signature` field is written empty on purpose. Producing it requires the
/// private key, which belongs to the developer and never to this tool; the
/// caller is told which OpenSSL command fills it in.
fn updater_fragment_json(
  platform : String,
  version : String,
  published_at : String,
  url : String,
  size : Int64,
  sha256 : String,
) -> String {
  let builder = StringBuilder::new()
  builder <+
    $|{
    $|  "schema_version": 1,
    $|  "version": "\{version}",
    $|  "published_at": "\{published_at}",
    $|  "platforms": {
    $|    "\{platform}": {
    $|      "kind": "full",
    $|      "url": "\{url}",
    $|      "size": \{size},
    $|      "sha256": "\{sha256}",
    $|      "signature": ""
    $|    }
    $|  }
    $|}
    $|
  builder.to_string()
}

///|
/// Writes update metadata beside the packaged artifacts.
///
/// Two files are produced: the artifact digest, and a manifest fragment with
/// every field except the signature. Signing is a separate step the developer
/// runs with their own key, so this command stops exactly where secret material
/// would otherwise be required.
pub async fn write_updater_metadata(
  plan : PackagePlan,
  base_url : String,
  published_at : String,
) -> Unit raise UpdaterMetadataError {
  guard base_url.has_prefix("https://") else {
    raise InvalidBaseUrl(url=base_url)
  }
  let platform = @cef.current_platform_id() catch {
    error => raise UnknownPlatform(detail=@debug.render(Repr(error)))
  }
  let artifact = match updater_artifact_path(plan) {
    Some(path) => path
    None => raise NoDistributableArtifact
  }
  let name = path_basename(artifact)
  let (sha256, size) = artifact_digest_and_size(artifact)
  let trimmed = base_url.trim_end(chars="/").to_owned()
  let fragment = updater_fragment_json(
    platform,
    plan.version,
    published_at,
    "\{trimmed}/\{name}",
    size,
    sha256,
  )
  verify_fragment_decodes(fragment)
  let digest_path = "\{artifact}.sha256"
  let fragment_path = resolve_path(plan.output, "latest-\{platform}.json")
  write_text(digest_path, "\{sha256}  \{name}\n") catch {
    error =>
      raise UnreadableArtifact(
        path=digest_path,
        detail=@debug.render(Repr(error)),
      )
  }
  write_text(fragment_path, fragment) catch {
    error =>
      raise UnreadableArtifact(
        path=fragment_path,
        detail=@debug.render(Repr(error)),
      )
  }
  println("Wrote artifact digest: \{digest_path}")
  println("Wrote manifest fragment: \{fragment_path}")
  println(
    (
      $|
      $|Sign the artifact with your own key, then paste the hexadecimal
      $|signature into the fragment's "signature" field:
      $|
      $|  openssl dgst -sha256 -sign updater.pem -out \{name}.sig \{name}
      $|  xxd -p -c 1024 \{name}.sig
    ),
  )
}

///|
/// A signature that is syntactically valid but obviously not real.
///
/// The emitted fragment carries an empty signature, which the decoder rejects
/// by design. Substituting this placeholder lets every other field be decoded
/// with the same parser the runtime uses, so a malformed version, platform
/// identifier, URL, or digest fails at package time instead of at every
/// installation.
let placeholder_signature : String = "00"

///|
/// Decodes the emitted fragment to prove the runtime will be able to read it.
fn verify_fragment_decodes(
  fragment : String,
) -> Unit raise UpdaterMetadataError {
  let probe = fragment.replace(
    old="\"signature\": \"\"",
    new="\"signature\": \"\{placeholder_signature}\"",
  )
  let _ = @updater.Manifest::parse(probe) catch {
    error => raise UndecodableFragment(detail=error.message())
  }
}
