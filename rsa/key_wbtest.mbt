///|
fn parse_error(text : String) -> KeyError {
  let _ = PublicKey::parse(text) catch { error => return error }
  abort("expected the key to be rejected")
}

///|
/// Test-only encoding for key-policy cases. The accepted signature vectors use
/// PEM exported independently by OpenSSL, not this encoder.
fn test_key_pem(
  modulus : @bigint.BigInt,
  exponent : @bigint.BigInt,
) -> String raise {
  let n = @asn1.encode_integer(modulus)
  let e = @asn1.encode_integer(exponent)
  let encoded = @asn1.encode_sequence([n[:], e[:]])
  @pem.encode_pem("RSA PUBLIC KEY", encoded[:])
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
test "accepts PEM whitespace and CRLF" {
  let text = "\n" + vector_public_key_pem.replace(old="\n", new="\r\n") + "\r\n"
  assert_eq(PublicKey::parse(text).bits(), 2048)
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
test "rejects non-RSA algorithms and malformed DER" {
  let ec_oid = @asn1.encode_object_identifier(
    @asn1.ObjectIdentifier::from_string("1.2.840.10045.2.1"),
  )
  let null = @asn1.encode_null()
  let algorithm = @asn1.encode_sequence([ec_oid[:], null[:]])
  let bits = @asn1.encode_bit_string(b"fixture"[:])
  let spki = @asn1.encode_sequence([algorithm[:], bits[:]])
  assert_true(
    parse_error(@pem.encode_pem("PUBLIC KEY", spki[:])) is Malformed(_),
  )
  for
    data in [
      b"", b"\x30\x82\xff\xff", b"\x30\x80", b"\x30\x00", b"\x30\x00\x00",
    ] {
    assert_true(
      parse_error(@pem.encode_pem("PUBLIC KEY", data[:])) is Malformed(_),
    )
  }
}

///|
test "rejects noncanonical or negative DER modulus integers" {
  let modulus = decode_hex(vector_modulus_hex)
  let bad_integer = @asn1.encode_tlv(
    @asn1.Tag::new(Universal, @asn1.TAG_INTEGER),
    (b"\x00\x00" + modulus)[:],
  )
  let exponent = @asn1.encode_int(65537)
  let der = @asn1.encode_sequence([bad_integer[:], exponent[:]])
  assert_true(
    parse_error(@pem.encode_pem("RSA PUBLIC KEY", der[:])) is Malformed(_),
  )
  assert_true(
    parse_error(
      test_key_pem(-vector_modulus(), @bigint.BigInt::from_int(65537)),
    )
    is Malformed(_),
  )
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
