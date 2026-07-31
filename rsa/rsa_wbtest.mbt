///|
fn vector_key() -> PublicKey raise {
  PublicKey::parse("rsa-sha256:\{vector_modulus_hex}:\{vector_exponent_hex}")
}

///|
fn vector_digest() -> Bytes raise {
  decode_hex(vector_digest_hex)
}

///|
fn vector_signature() -> Bytes raise {
  decode_hex(vector_signature_hex)
}

///|
/// Replaces one byte, for producing a signature that is well formed but wrong.
fn with_byte(source : Bytes, index : Int, value : Byte) -> Bytes {
  let out : Array[Byte] = []
  for position in 0..<source.length() {
    out.push(if position == index { value } else { source[position] })
  }
  Bytes::from_array(out[:])
}

///|
test "accepts a signature produced by OpenSSL" {
  assert_true(
    verify_pkcs1_sha256(vector_key(), vector_digest(), vector_signature()),
  )
}

///|
test "key metadata matches the vector" {
  let key = vector_key()
  assert_eq(key.size(), 256)
  assert_eq(key.bits(), 2048)
}

///|
test "rejects a signature for a different digest" {
  let digest = vector_digest()
  let altered = with_byte(digest, 0, digest[0] ^ b'\x01')
  assert_false(verify_pkcs1_sha256(vector_key(), altered, vector_signature()))
}

///|
test "rejects a single flipped bit anywhere in the signature" {
  let key = vector_key()
  let digest = vector_digest()
  let signature = vector_signature()
  // Sample the first, middle and last bytes rather than all 256, which keeps
  // the test fast while still covering the high, middle and low limbs.
  for index in [0, 1, 127, 128, 254, 255] {
    let altered = with_byte(signature, index, signature[index] ^ b'\x01')
    assert_false(verify_pkcs1_sha256(key, digest, altered))
  }
}

///|
test "rejects a signature whose length is not the modulus length" {
  let key = vector_key()
  let digest = vector_digest()
  let signature = vector_signature()
  // Short, including a left-stripped encoding of the same integer.
  assert_false(verify_pkcs1_sha256(key, digest, signature[1:].to_owned()))
  // Long, including a zero-extended encoding of the same integer.
  let extended : Array[Byte] = [b'\x00']
  for byte in signature {
    extended.push(byte)
  }
  assert_false(verify_pkcs1_sha256(key, digest, Bytes::from_array(extended[:])))
  assert_false(verify_pkcs1_sha256(key, digest, b""))
}

///|
test "rejects a signature representative that is not below the modulus" {
  let key = vector_key()
  let digest = vector_digest()
  // s = n is out of range for RSAVP1 even though it has the correct length.
  let modulus_bytes = decode_hex(vector_modulus_hex)
  assert_false(verify_pkcs1_sha256(key, digest, modulus_bytes))
  // s = 0 and s = 1 decrypt to 0 and 1, neither of which is a padded block.
  let zero : Array[Byte] = []
  for _ in 0..<key.size() {
    zero.push(b'\x00')
  }
  assert_false(verify_pkcs1_sha256(key, digest, Bytes::from_array(zero[:])))
  let one = with_byte(Bytes::from_array(zero[:]), key.size() - 1, b'\x01')
  assert_false(verify_pkcs1_sha256(key, digest, one))
}

///|
test "rejects a digest that is not 32 bytes" {
  let key = vector_key()
  let signature = vector_signature()
  let digest = vector_digest()
  assert_false(verify_pkcs1_sha256(key, digest[1:].to_owned(), signature))
  assert_false(verify_pkcs1_sha256(key, b"", signature))
}

///|
test "encodes the padded block exactly as RFC 8017 specifies" {
  let digest = vector_digest()
  let encoded = encode_pkcs1_sha256(digest, 256).unwrap()
  assert_eq(encoded.length(), 256)
  assert_eq(encoded[0], b'\x00')
  assert_eq(encoded[1], b'\x01')
  // 256 - 51 - 3 = 202 octets of 0xFF, then the separator.
  for index in 2..<204 {
    assert_eq(encoded[index], b'\xff')
  }
  assert_eq(encoded[204], b'\x00')
  // DigestInfo begins with the SHA-256 AlgorithmIdentifier sequence.
  assert_eq(encoded[205], b'\x30')
  assert_eq(encoded[206], b'\x31')
  // The digest occupies the final 32 octets.
  for index in 0..<32 {
    assert_eq(encoded[224 + index], digest[index])
  }
}

///|
test "refuses to encode when the modulus cannot hold a padded block" {
  let digest = vector_digest()
  // tLen is 51 and RFC 8017 requires at least eight 0xFF octets, so the
  // smallest permitted block is 1 + 1 + 8 + 1 + 51 = 62 bytes.
  assert_true(encode_pkcs1_sha256(digest, 62) is Some(_))
  assert_true(encode_pkcs1_sha256(digest, 61) is None)
  assert_true(encode_pkcs1_sha256(digest, 0) is None)
  assert_true(encode_pkcs1_sha256(b"\x00", 256) is None)
}

///|
test "compares byte strings without an early exit" {
  assert_true(bytes_equal_no_early_exit(b"\x01\x02\x03", b"\x01\x02\x03"))
  assert_false(bytes_equal_no_early_exit(b"\x01\x02\x03", b"\x01\x02\x04"))
  assert_false(bytes_equal_no_early_exit(b"\x01\x02\x03", b"\x81\x02\x03"))
  assert_false(bytes_equal_no_early_exit(b"\x01\x02", b"\x01\x02\x03"))
  assert_true(bytes_equal_no_early_exit(b"", b""))
}
