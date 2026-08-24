///|
/// The smallest modulus this package will accept.
///
/// 1024-bit RSA is considered broken for signatures and 2048 is the current
/// floor in every serious guideline. Refusing a short key is a security control
/// in its own right: a key that is too small verifies signatures perfectly well
/// and offers no protection.
pub let minimum_modulus_bits : Int = 2048

///|
let algorithm_tag : String = "rsa-sha256"

///|
/// An RSA public key that verifies RSASSA-PKCS1-v1_5 signatures over SHA-256.
pub struct PublicKey {
  modulus : @bigint.BigInt
  exponent : @bigint.BigInt
  /// Length of the modulus in bytes. This is `k` in RFC 8017 and fixes the
  /// exact length every signature and encoded message must have.
  size : Int
}

///|
/// Parses a trusted public key.
///
/// The encoding is `rsa-sha256:<modulus hex>:<exponent hex>`, big-endian and
/// unsigned. The algorithm tag is part of the stored key so that migrating to a
/// different scheme later does not require a release that existing
/// installations are unable to accept.
pub fn PublicKey::parse(text : String) -> PublicKey raise KeyError {
  let parts = text.split(":").collect()
  guard parts.length() == 3 else {
    raise Malformed(
      detail="expected \{algorithm_tag}:<modulus hex>:<exponent hex>",
    )
  }
  let tag = parts[0].to_owned()
  guard tag == algorithm_tag else { raise UnknownAlgorithm(tag~) }
  let modulus_bytes = decode_hex(parts[1].to_owned())
  let exponent_bytes = decode_hex(parts[2].to_owned())

  // A leading zero byte would let two different texts denote the same modulus
  // with different values of `k`, and `k` decides which signature lengths are
  // accepted. Requiring a canonical encoding keeps that mapping one to one.
  guard modulus_bytes[0] != b'\x00' else { raise NonCanonicalModulus }
  let modulus = @bigint.BigInt::from_octets(modulus_bytes[:])
  let bits = modulus.bit_length()
  guard bits >= minimum_modulus_bits else {
    raise ModulusTooSmall(bits~, minimum=minimum_modulus_bits)
  }
  let exponent = @bigint.BigInt::from_octets(exponent_bytes[:])
  // e = 1 would make the signature equal to the encoded message, so anyone
  // could produce one. Even exponents are not valid RSA exponents at all.
  guard exponent.compare_int(3) >= 0 else {
    raise InvalidExponent(detail="must be at least 3")
  }
  guard exponent.compare(modulus) < 0 else {
    raise InvalidExponent(detail="must be smaller than the modulus")
  }
  guard exponent.is_odd() else { raise InvalidExponent(detail="must be odd") }
  PublicKey::{ modulus, exponent, size: modulus_bytes.length(), }
}

///|
/// Returns the modulus length in bytes.
pub fn PublicKey::size(self : PublicKey) -> Int {
  self.size
}

///|
/// Returns the modulus length in bits.
pub fn PublicKey::bits(self : PublicKey) -> Int {
  self.modulus.bit_length()
}

///|
fn @bigint.BigInt::is_odd(self : @bigint.BigInt) -> Bool {
  (self % @bigint.BigInt::from_int(2)).compare_int(0) != 0
}
