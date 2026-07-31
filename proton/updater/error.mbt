///|
/// A reason an update was not accepted.
///
/// Every variant is a refusal. There is no variant meaning "checked and could
/// not tell": a check that cannot reach a conclusion is a check that failed,
/// and the caller must treat it as such.
pub(all) suberror UpdateError {
  FetchFailed(url~ : String, detail~ : String)
  ManifestSignatureInvalid
  ManifestUndecodable(detail~ : String)
  ManifestStale(published_at~ : String, oldest_accepted~ : String)
  MalformedSignature(url~ : String)
  UntrustedKey(detail~ : String)
  ArtifactSizeMismatch(expected~ : Int64, actual~ : Int64)
  ArtifactDigestMismatch(expected~ : String, actual~ : String)
  ArtifactSignatureInvalid
} derive(Debug, Eq)

///|
pub fn UpdateError::message(self : UpdateError) -> String {
  match self {
    FetchFailed(url~, detail~) => "cannot fetch \{url}: \{detail}"
    ManifestSignatureInvalid =>
      "the update manifest is not signed by a trusted key"
    ManifestUndecodable(detail~) =>
      "the update manifest is malformed: \{detail}"
    ManifestStale(published_at~, oldest_accepted~) =>
      "the update manifest was published at \{published_at}, older than the accepted \{oldest_accepted}"
    MalformedSignature(url~) => "the signature at \{url} is not hexadecimal"
    UntrustedKey(detail~) => "a configured trusted key is unusable: \{detail}"
    ArtifactSizeMismatch(expected~, actual~) =>
      "the artifact is \{actual} bytes, the manifest declares \{expected}"
    ArtifactDigestMismatch(expected~, actual~) =>
      "the artifact digest is \{actual}, the manifest declares \{expected}"
    ArtifactSignatureInvalid => "the artifact is not signed by a trusted key"
  }
}

///|
impl Show for UpdateError with fn output(self, logger) {
  logger.write_string(self.message())
}
