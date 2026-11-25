///|
/// A PEM envelope or DER structure could not be read as an RSA public key.
pub suberror InvalidKey {
  InvalidKey(String)
}

///|
/// Reads one PKCS#1 or SubjectPublicKeyInfo PEM public key and returns its
/// modulus and public exponent. The caller enforces RSA key policy.
pub fn parse_rsa_public_key(
  text : StringView,
) -> (@bigint.BigInt, @bigint.BigInt) raise InvalidKey {
  // A CRLF boundary contributes an empty line, which PEM readers ignore.
  let lines = text.split("\r").flat_map(part => part.split("\n"))
  let mut result = None
  for line in lines {
    let line = line.trim()
    guard line.has_prefix("-----BEGIN ") && line.has_suffix("-----") else {
      continue
    }
    guard result is None else {
      raise InvalidKey("expected exactly one PEM block")
    }
    let (end_line, spki) = match line {
      "-----BEGIN RSA PUBLIC KEY-----" =>
        ("-----END RSA PUBLIC KEY-----", false)
      "-----BEGIN PUBLIC KEY-----" => ("-----END PUBLIC KEY-----", true)
      _ => raise InvalidKey("expected PUBLIC KEY or RSA PUBLIC KEY PEM")
    }
    let der = read_body(lines, end_line)
    result = Some(read_key(der[:], spki))
  }
  guard result is Some(key) else { raise InvalidKey("no PEM public key found") }
  key
}

///|
fn read_body(
  lines : Iter[StringView],
  end_line : String,
) -> Bytes raise InvalidKey {
  let body = StringBuilder()
  for line in lines {
    let line = line.trim()
    if line == end_line[:] {
      // Complete the last quartet so the decoder checks the unused padding bits.
      let encoded = body.to_string()
      let padded = match encoded.length() % 4 {
        0 => encoded
        2 => encoded + "=="
        3 => encoded + "="
        _ => raise InvalidKey("invalid PEM base64 length")
      }
      return @base64.decode(padded) catch {
        _ => raise InvalidKey("invalid PEM base64")
      }
    }
    if line.has_prefix("-----END ") {
      raise InvalidKey("mismatched PEM end line")
    }
    // Encapsulated headers may precede the base64 payload.
    if body.is_empty() &&
      line.split_once(": ") is Some((name, _)) &&
      !name.is_empty() {
      continue
    }
    for ch in line {
      match ch {
        ' ' | '\t' => ()
        _ => body.write_char(ch)
      }
    }
  }
  raise InvalidKey("missing PEM end line")
}

///|
fn read_key(
  der : BytesView,
  spki : Bool,
) -> (@bigint.BigInt, @bigint.BigInt) raise InvalidKey {
  let outer = only_field(der, b'\x30')
  let fields = if spki {
    let (algorithm, key) = take_field(outer, b'\x30')
    // DER encoding of rsaEncryption (1.2.840.113549.1.1.1) and NULL.
    guard algorithm ==
      b"\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x01\x05\x00"[:] else {
      raise InvalidKey("expected rsaEncryption with NULL parameters")
    }
    let bits = only_field(key, b'\x03')
    guard bits is [b'\x00', .. payload] else {
      raise InvalidKey("expected a byte-aligned RSA public key")
    }
    only_field(payload, b'\x30')
  } else {
    outer
  }
  let (modulus, rest) = take_field(fields, b'\x02')
  let exponent = only_field(rest, b'\x02')
  (integer(modulus), integer(exponent))
}
