///|
fn parse_error(text : String) -> KeyError {
  let _ = PublicKey::parse(text) catch { error => return error }
  abort("expected \{text} to be rejected")
}

///|
test "accepts the vector key" {
  let key = PublicKey::parse(
    "rsa-sha256:\{vector_modulus_hex}:\{vector_exponent_hex}",
  )
  assert_eq(key.size(), 256)
  assert_eq(key.bits(), 2048)
}

///|
test "rejects a key whose algorithm tag is not the expected one" {
  assert_eq(
    parse_error("ed25519:\{vector_modulus_hex}:010001"),
    UnknownAlgorithm(tag="ed25519"),
  )
  assert_eq(
    parse_error("RSA-SHA256:\{vector_modulus_hex}:010001"),
    UnknownAlgorithm(tag="RSA-SHA256"),
  )
}

///|
test "rejects a key that is not three colon-separated fields" {
  assert_true(parse_error("rsa-sha256:\{vector_modulus_hex}") is Malformed(_))
  assert_true(parse_error("\{vector_modulus_hex}:010001") is Malformed(_))
  assert_true(
    parse_error("rsa-sha256:\{vector_modulus_hex}:010001:extra") is Malformed(_),
  )
  assert_true(parse_error("") is Malformed(_))
}

///|
test "rejects hexadecimal that is malformed" {
  // Odd length.
  assert_true(parse_error("rsa-sha256:\{vector_modulus_hex}:1") is Malformed(_))
  // Not a hexadecimal digit, including the whitespace and separators a
  // permissive decoder would skip.
  assert_true(
    parse_error("rsa-sha256:\{vector_modulus_hex}:01000g") is Malformed(_),
  )
  assert_true(
    parse_error("rsa-sha256:\{vector_modulus_hex}:01 00 01") is Malformed(_),
  )
  assert_true(
    parse_error("rsa-sha256:\{vector_modulus_hex}:0x010001") is Malformed(_),
  )
  // Empty.
  assert_true(parse_error("rsa-sha256:\{vector_modulus_hex}:") is Malformed(_))
  assert_true(parse_error("rsa-sha256::010001") is Malformed(_))
}

///|
test "rejects a modulus written with a leading zero byte" {
  // The same integer, but the leading zero would make `k` 257 rather than 256
  // and therefore change which signature lengths are accepted.
  assert_eq(
    parse_error("rsa-sha256:00\{vector_modulus_hex}:010001"),
    NonCanonicalModulus,
  )
}

///|
test "rejects a modulus below the minimum size" {
  // 1024 bits, canonical, with a valid exponent.
  // 256 hex digits is 128 bytes is 1024 bits, with the top bit set.
  let short_modulus = "c" + "0".repeat(255)
  assert_eq(
    parse_error("rsa-sha256:\{short_modulus}:010001"),
    ModulusTooSmall(bits=1024, minimum=2048),
  )
}

///|
test "rejects exponents that cannot be used for verification" {
  // e = 1 makes the signature equal to the encoded block, so anyone can forge.
  assert_true(
    parse_error("rsa-sha256:\{vector_modulus_hex}:01") is InvalidExponent(_),
  )
  assert_true(
    parse_error("rsa-sha256:\{vector_modulus_hex}:00") is InvalidExponent(_),
  )
  // Even exponents are not valid RSA exponents.
  assert_true(
    parse_error("rsa-sha256:\{vector_modulus_hex}:010002") is InvalidExponent(_),
  )
  // e must be smaller than n.
  assert_true(
    parse_error("rsa-sha256:\{vector_modulus_hex}:\{vector_modulus_hex}")
    is InvalidExponent(_),
  )
}

///|
test "accepts a large but valid exponent" {
  let key = PublicKey::parse("rsa-sha256:\{vector_modulus_hex}:0100000001")
  assert_eq(key.size(), 256)
}
