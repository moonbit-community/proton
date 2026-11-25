///|
/// The smallest modulus this package will accept.
///
/// 1024-bit RSA is considered broken for signatures and 2048 is the current
/// floor in every serious guideline. Refusing a short key is a security control
/// in its own right: a key that is too small verifies signatures perfectly well
/// and offers no protection.
pub let minimum_modulus_bits : Int32 = 2048

///|
/// An RSA public key that verifies RSASSA-PKCS1-v1_5 signatures over SHA-256.
pub struct PublicKey {
  modulus : @bigint.BigInt
  exponent : @bigint.BigInt
  /// Length of the modulus in bytes. This is `k` in RFC 8017 and fixes the
  /// exact length every signature and encoded message must have.
  size : Int32
}

///|
/// Parses a PEM-encoded RSA public key.
///
/// Accepts SubjectPublicKeyInfo (`PUBLIC KEY`, produced by `openssl pkey -pubout`)
/// and PKCS#1 (`RSA PUBLIC KEY`). Private keys and certificates are not accepted.
pub fn PublicKey::parse(text : String) -> PublicKey raise KeyError {
  let (modulus, exponent) = @pki.parse_rsa_public_key(text[:]) catch {
    @pki.InvalidKey(detail) => raise Malformed(detail~)
  }
  guard modulus.compare_int(0) > 0 else {
    raise Malformed(detail="RSA modulus must be positive")
  }
  let bits = modulus.bit_length()
  guard bits >= minimum_modulus_bits else {
    raise ModulusTooSmall(bits~, minimum=minimum_modulus_bits)
  }
  // e = 1 would make the signature equal to the encoded message, so anyone
  // could produce one. Even exponents are not valid RSA exponents at all.
  guard exponent.compare_int(3) >= 0 else {
    raise InvalidExponent(detail="must be at least 3")
  }
  guard exponent.compare(modulus) < 0 else {
    raise InvalidExponent(detail="must be smaller than the modulus")
  }
  guard exponent.is_odd() else { raise InvalidExponent(detail="must be odd") }
  PublicKey::{ modulus, exponent, size: (bits + 7) / 8, }
}

///|
/// Returns the modulus length in bytes.
pub fn PublicKey::size(self : PublicKey) -> Int32 {
  self.size
}

///|
/// Returns the modulus length in bits.
pub fn PublicKey::bits(self : PublicKey) -> Int32 {
  self.modulus.bit_length()
}

///|
fn @bigint.BigInt::is_odd(self : @bigint.BigInt) -> Bool {
  (self % @bigint.BigInt::from_int(2)).compare_int(0) != 0
}
