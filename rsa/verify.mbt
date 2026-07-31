///|
/// Verifies an RSASSA-PKCS1-v1_5 signature over a SHA-256 digest.
///
/// `digest` is the 32-byte SHA-256 of the signed content; the caller hashes,
/// which lets a large artifact be streamed rather than held in memory.
/// `signature` is the raw big-endian signature, exactly `key.size()` bytes.
///
/// Returns `true` only for a signature that verifies. Every other outcome —
/// wrong length, out-of-range signature, malformed padding, wrong digest — is
/// `false`. Verification deliberately cannot raise: a caller that distinguished
/// "invalid" from "failed to check" would eventually treat one as the other,
/// and this function decides whether foreign code is allowed to run.
pub fn verify_pkcs1_sha256(
  key : PublicKey,
  digest : Bytes,
  signature : Bytes,
) -> Bool {
  if digest.length() != sha256_digest_length {
    return false
  }

  // RFC 8017 section 8.2.2 step 1: the signature is `k` bytes, always. A
  // shorter signature is not zero-extended, because accepting several encodings
  // of one value is how signature malleability starts.
  if signature.length() != key.size {
    return false
  }
  let representative = @bigint.BigInt::from_octets(signature[:])

  // RSAVP1 step 1: reject s outside [0, n-1]. `from_octets` cannot produce a
  // negative value, so only the upper bound needs a test.
  if representative.compare(key.modulus) >= 0 {
    return false
  }
  let encoded = representative.pow(key.exponent, modulus=key.modulus)

  // I2OSP with an explicit width check. `to_octets(length=)` left-pads a short
  // value but does not truncate a long one, so the returned length is the only
  // reliable evidence that the result fits in `k` bytes.
  let encoded_bytes = encoded.to_octets(length=key.size)
  if encoded_bytes.length() != key.size {
    return false
  }
  match encode_pkcs1_sha256(digest, key.size) {
    None => false
    Some(expected) => bytes_equal_no_early_exit(encoded_bytes, expected)
  }
}
