///|
fn parse_error(text : String) -> KeyError {
  let _ = PublicKey::parse(text) catch { error => return error }
  abort("expected the key to be rejected")
}

///|
/// Test-only encoding for key-policy cases. The accepted signature vectors use
/// PEM exported independently by OpenSSL, not this encoder.
fn test_key_pem(modulus : @bigint.BigInt, exponent : @bigint.BigInt) -> String {
  let n = test_unsigned_integer(modulus)
  let e = test_unsigned_integer(exponent)
  test_pem("RSA PUBLIC KEY", test_field(b'\x30', n + e))
}

///|
fn test_pem(label : String, der : Bytes) -> String {
  "-----BEGIN \{label}-----\n\{@base64.encode(der[:])}\n-----END \{label}-----"
}

///|
/// The generated test fixtures are all smaller than 64 KiB.
fn test_field(tag : Byte, value : Bytes) -> Bytes {
  let n = value.length()
  let prefix : Array[Byte] = if n < 128 {
    [tag, n.to_byte()]
  } else if n < 256 {
    [tag, b'\x81', n.to_byte()]
  } else {
    [tag, b'\x82', (n >> 8).to_byte(), n.to_byte()]
  }
  Bytes::from_array(prefix[:]) + value
}

///|
fn test_unsigned_integer(n : @bigint.BigInt) -> Bytes {
  let bytes = n.to_octets()
  let value = if bytes.is_empty() || bytes[0] >= b'\x80' {
    b"\x00" + bytes
  } else {
    bytes
  }
  test_field(b'\x02', value)
}

///|
fn vector_modulus() -> @bigint.BigInt raise {
  @bigint.BigInt::from_octets(decode_hex(vector_modulus_hex)[:])
}

///|
test "accepts OpenSSL SubjectPublicKeyInfo and PKCS1 public keys" {
  for text in [vector_public_key_pem, vector_pkcs1_public_key_pem] {
    let key = PublicKey::parse(text)
    assert_eq(key.size(), 256)
    assert_eq(key.bits(), 2048)
    assert_true(verify_pkcs1_sha256(key, vector_digest(), vector_signature()))
  }
}

///|
test "accepts PEM whitespace with LF, CRLF and CR line endings" {
  for ending in ["\n", "\r\n", "\r"] {
    let text = ending +
      vector_public_key_pem.replace(old="\n", new=ending) +
      ending
    let key = PublicKey::parse(text)
    assert_true(verify_pkcs1_sha256(key, vector_digest(), vector_signature()))
  }
}

///|
test "rejects malformed PEM and the removed custom key format" {
  for
    text in [
      "",
      "not PEM",
      "rsa-sha256:\{vector_modulus_hex}:010001",
      vector_public_key_pem.replace(
        old="END PUBLIC KEY",
        new="END RSA PUBLIC KEY",
      ),
      vector_public_key_pem + "\n" + vector_public_key_pem,
      "-----BEGIN PUBLIC KEY-----\n%%%\n-----END PUBLIC KEY-----",
    ] {
    assert_true(parse_error(text) is Malformed(_))
  }
}

///|
test "rejects private keys and certificates instead of treating them as public keys" {
  for label in ["PRIVATE KEY", "RSA PRIVATE KEY", "CERTIFICATE"] {
    let pem = vector_public_key_pem.replace(old="PUBLIC KEY", new=label)
    assert_true(parse_error(pem) is Malformed(_))
  }
}

///|
test "SPKI requires rsaEncryption, NULL parameters and octet-aligned key bits" {
  let modulus = test_unsigned_integer(vector_modulus())
  let exponent = test_unsigned_integer(@bigint.BigInt::from_int(65537))
  let pkcs1 = test_field(b'\x30', modulus + exponent)
  let rsa_oid = b"\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x01"
  let ec_oid = b"\x06\x07\x2a\x86\x48\xce\x3d\x02\x01"
  let null_der = b"\x05\x00"
  fn spki(oid : Bytes, parameters : Bytes, unused_bits : Byte) -> String {
    let algorithm = test_field(b'\x30', oid + parameters)
    let bits = test_field(b'\x03', Bytes::from_array([unused_bits]) + pkcs1)
    test_pem("PUBLIC KEY", test_field(b'\x30', algorithm + bits))
  }

  let key = PublicKey::parse(spki(rsa_oid, null_der, 0))
  assert_true(verify_pkcs1_sha256(key, vector_digest(), vector_signature()))
  assert_true(parse_error(spki(ec_oid, null_der, 0)) is Malformed(_))
  assert_true(parse_error(spki(rsa_oid, b"", 0)) is Malformed(_))
  assert_true(parse_error(spki(rsa_oid, null_der, 1)) is Malformed(_))
}

///|
test "rejects malformed DER" {
  for
    data in [
      b"", b"\x30\x82\xff\xff", b"\x30\x80", b"\x30\x00", b"\x30\x00\x00",
    ] {
    assert_true(parse_error(test_pem("PUBLIC KEY", data)) is Malformed(_))
  }
}

///|
test "rejects noncanonical or negative DER modulus integers" {
  for
    der in [
      b"\x30\x07\x02\x02\x00\x01\x02\x01\x03", // redundant sign octet
       b"\x30\x06\x02\x01\xff\x02\x01\x03", // modulus -1
    ] {
    assert_true(parse_error(test_pem("RSA PUBLIC KEY", der)) is Malformed(_))
  }
}

///|
test "rejects a modulus below the minimum size" {
  let text = test_key_pem(
    @bigint.BigInt::from_int(1) << 1023,
    @bigint.BigInt::from_int(65537),
  )
  assert_eq(parse_error(text), ModulusTooSmall(bits=1024, minimum=2048))
}

///|
test "rejects exponents that cannot be used for verification" {
  let n = vector_modulus()
  for exponent in [0, 1, 2, 65538] {
    assert_true(
      parse_error(test_key_pem(n, @bigint.BigInt::from_int(exponent)))
      is InvalidExponent(_),
    )
  }
  assert_true(parse_error(test_key_pem(n, n)) is InvalidExponent(_))
}

///|
test "accepts a large but valid exponent" {
  let text = test_key_pem(
    vector_modulus(),
    @bigint.BigInt::from_int64(0x0100000001L),
  )
  assert_eq(PublicKey::parse(text).size(), 256)
}
