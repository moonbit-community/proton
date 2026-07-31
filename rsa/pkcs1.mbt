///|
/// The DER `DigestInfo` prefix for SHA-256, from RFC 8017 section 9.2.
///
/// It encodes `SEQUENCE { SEQUENCE { OID 2.16.840.1.101.3.4.2.1, NULL },
/// OCTET STRING (32) }`. The 32-byte digest follows it, giving a 51-byte
/// `DigestInfo`. This package stores the bytes rather than building them,
/// because the value is fixed and a builder would be one more thing to get
/// wrong.
let sha256_digest_info_prefix : Bytes = b"\x30\x31\x30\x0d\x06\x09\x60\x86\x48\x01\x65\x03\x04\x02\x01\x05\x00\x04\x20"

///|
/// Length of a SHA-256 digest in bytes.
pub let sha256_digest_length : Int = 32

///|
/// Builds the EMSA-PKCS1-v1_5 encoded message for a SHA-256 digest.
///
/// `EM = 0x00 || 0x01 || PS || 0x00 || DigestInfo`, where `PS` is `0xFF`
/// repeated so that `EM` is exactly `size` bytes.
///
/// Verification builds this value and compares it to what the signature
/// decrypts to. It never inspects the decrypted block field by field. That
/// choice is the whole defence against Bleichenbacher's 2006 forgery, which
/// works precisely against verifiers that walk the padding and stop at the
/// digest instead of insisting on the entire block.
///
/// Returns `None` when the modulus cannot hold a correctly padded block. RFC
/// 8017 requires at least eight `0xFF` octets, so `size` must be at least
/// `tLen + 11`.
fn encode_pkcs1_sha256(digest : Bytes, size : Int) -> Bytes? {
  if digest.length() != sha256_digest_length {
    return None
  }
  let info_length = sha256_digest_info_prefix.length() + digest.length()
  if size < info_length + 11 {
    return None
  }
  let padding_length = size - info_length - 3
  let out : Array[Byte] = []
  out.push(b'\x00')
  out.push(b'\x01')
  for _ in 0..<padding_length {
    out.push(b'\xff')
  }
  out.push(b'\x00')
  for byte in sha256_digest_info_prefix {
    out.push(byte)
  }
  for byte in digest {
    out.push(byte)
  }
  Some(Bytes::from_array(out[:]))
}

///|
/// Compares two byte strings without an early exit.
///
/// Everything compared here is public, so a timing signal leaks nothing. The
/// function is written this way regardless: a verification routine that returns
/// as soon as it finds a difference is the shape that becomes a vulnerability
/// the moment someone reuses it on secret data.
fn bytes_equal_no_early_exit(left : Bytes, right : Bytes) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut difference = 0
  for index in 0..<left.length() {
    difference = difference | (left[index].to_int() ^ right[index].to_int())
  }
  difference == 0
}
