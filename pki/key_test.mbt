///|
test "single PEM block with headers, surrounding text and omitted padding" {
  // DER SEQUENCE { INTEGER 128, INTEGER 3 }. The leading zero is required.
  let pem =
    #|prologue
    #|-----BEGIN RSA PUBLIC KEY-----
    #|Comment: exported key
    #|
    #|MAcC AgCA
    #|AgED
    #|-----END RSA PUBLIC KEY-----
    #|epilogue
  let (n, e) = @proton_pki.parse_rsa_public_key(pem[:])
  assert_eq(n.to_string(), "128")
  assert_eq(e.to_string(), "3")
  let unpadded =
    #|-----BEGIN RSA PUBLIC KEY-----
    #|MAYCAQECAQM
    #|-----END RSA PUBLIC KEY-----
  let (n, _) = @proton_pki.parse_rsa_public_key(unpadded[:])
  assert_eq(n.to_string(), "1")
}

///|
test "rejects non-minimal lengths, overlong fields and trailing DER" {
  let fields = b"\x02\x01\x01\x02\x01\x03"
  for
    der in [
      b"\x30\x81\x06" + fields,
      b"\x30\x82\x00\x06" + fields,
      b"\x30\x84\xff\xff\xff\xff" + fields,
      b"\x30\x07" + fields,
      b"\x30\x06" + fields + b"\x00",
      b"\x30\x07" + fields + b"\x00",
      b"\x30\x07\x02\x01\x01\x02\x02\xff\xff",
    ] {
    let pem = "-----BEGIN RSA PUBLIC KEY-----\n\{@base64.encode(der[:])}\n-----END RSA PUBLIC KEY-----"
    let result = Some(@proton_pki.parse_rsa_public_key(pem[:])) catch {
      _ => None
    }
    assert_true(result is None)
  }
}
