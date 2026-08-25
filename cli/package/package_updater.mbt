///|
/// An update manifest fragment could not be produced.
pub(all) suberror UpdaterMetadataError {
  NoDistributableArtifact
  UnreadableArtifact(path~ : String, detail~ : String)
  InvalidBaseUrl(url~ : String)
  MissingPublishedAt
  MissingRevision
  InvalidRevision(value~ : String)
  UndecodableFragment(detail~ : String)
} derive(Eq)

///|
pub extend UpdaterMetadataError with Eq::{not_equal, equal}

///|
pub extend UpdaterMetadataError with Show::{to_string, output}

///|
priv enum UpdatePlatform {
  Macos
  Windows
  Linux
}

///|
fn update_platform_of(platform : String) -> UpdatePlatform? {
  if platform.has_prefix("darwin-") {
    Some(Macos)
  } else if platform.has_prefix("win32-") {
    Some(Windows)
  } else if platform.has_prefix("linux-") {
    Some(Linux)
  } else {
    None
  }
}

///|
pub fn UpdaterMetadataError::message(self : UpdaterMetadataError) -> String {
  match self {
    NoDistributableArtifact =>
      (
        $|no distributable artifact to describe
        $|
        $|An update is downloaded as a single file, so the manifest fragment
        $|needs a target that produces one: zip or dmg on macOS, nsis on
        $|Windows, appimage on Linux. A staged app directory cannot be fetched.
      )
    UnreadableArtifact(path~, detail~) => "cannot read \{path}: \{detail}"
    InvalidBaseUrl(url~) => "updater base URL must begin with https://: \{url}"
    MissingPublishedAt =>
      (
        $|--updater-published-at is required with --updater-base-url
        $|
        $|The instant is supplied rather than read from the clock so that a
        $|release is reproducible. Use UTC, to the second:
        $|
        $|  --updater-published-at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      )
    MissingRevision =>
      (
        $|--updater-revision is required with --updater-base-url
        $|
        $|Use a positive release sequence that never decreases or resets.
      )
    InvalidRevision(value~) =>
      "updater revision must be a positive unsigned 64-bit integer: \{value}"
    UndecodableFragment(detail~) =>
      "the emitted manifest fragment does not decode: \{detail}"
  }
}

///|
fn path_basename(path : String) -> String {
  let native_path : @path.Path = path
  native_path.basename().to_owned()
}

///|
async fn write_updater_file(path : String, text : String) -> Unit {
  @async_fs.write_file(path, text, create_mode=CreateOrTruncate)
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
/// The updater's anti-rollback anchor. Written into the package metadata
/// directory and read back by the native updater to decide whether an offered
/// revision moves forward.
///
/// macOS has no need of it -- its revision lives in the code-signed
/// `Info.plist`. The other two hosts have no signature to carry it, so the
/// value lands in a plain file that is still awkward to forge in place: an
/// AppImage's squashfs is read-only, and a Windows install tree sits under
/// Program Files.
///
/// Held as a decimal string for the same reason macOS holds one: it preserves
/// the full uint64 range that plist integers and JSON doubles do not.
/// Returns the artifact an update would download.
///
/// Always exactly one file, so a staged directory is never a candidate. Where
/// a host builds more than one candidate the tie is broken by what the apply
/// path wants: on Windows the installer, because applying an update re-runs
/// it; on macOS the zip, because it is the smaller of the two and needs no
/// mounting to expand.
fn updater_artifact_path(
  artifacts : Array[String],
  platform : String,
) -> String? {
  let first_with_suffix = fn(suffix : String) -> String? {
    for artifact in artifacts {
      if artifact.to_lower().has_suffix(suffix) {
        return Some(artifact)
      }
    }
    None
  }
  match update_platform_of(platform) {
    Some(Macos) =>
      match first_with_suffix(".app.zip") {
        Some(path) => Some(path)
        None => first_with_suffix(".dmg")
      }
    Some(Windows) => first_with_suffix("-setup.exe")
    Some(Linux) => first_with_suffix(".appimage")
    None => None
  }
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
  revision : UInt64,
  published_at : String,
  url : String,
  size : Int64,
  sha256 : String,
) -> String {
  let builder = StringBuilder()
  builder <+
    $|{
    $|  "schema_version": 2,
    $|  "version": "\{version}",
    $|  "revision": \{revision},
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
async fn write_updater_metadata(
  plan : PackagePlan,
  artifacts : Array[String],
  platform : String,
  base_url : String,
  published_at : String,
) -> Unit raise UpdaterMetadataError {
  guard plan.update_revision > 0UL else { raise MissingRevision }
  guard base_url.has_prefix("https://") else {
    raise InvalidBaseUrl(url=base_url)
  }
  let artifact = match updater_artifact_path(artifacts, platform) {
    Some(path) => path
    None => raise NoDistributableArtifact
  }
  let name = path_basename(artifact)
  let (sha256, size) = artifact_digest_and_size(artifact)
  let trimmed = base_url.trim_end(chars="/").to_owned()
  let fragment = updater_fragment_json(
    platform,
    plan.version,
    plan.update_revision,
    published_at,
    "\{trimmed}/\{name}",
    size,
    sha256,
  )
  verify_fragment_decodes(fragment)
  let digest_path = "\{artifact}.sha256"
  let fragment_path = @fsutil.resolve_path(
    plan.output,
    "latest-\{platform}.json",
  )
  write_updater_file(digest_path, "\{sha256}  \{name}\n") catch {
    error =>
      raise UnreadableArtifact(
        path=digest_path,
        detail=@debug.render(Repr(error)),
      )
  }
  write_updater_file(fragment_path, fragment) catch {
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
