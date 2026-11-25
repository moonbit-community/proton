///|
/// Splits one definite-length DER field from the remaining input.
fn take_field(
  input : BytesView,
  tag : Byte,
) -> (BytesView, BytesView) raise InvalidKey {
  guard input is [actual, first, .. rest] && actual == tag else {
    raise InvalidKey("missing or unexpected DER field")
  }
  let mut length = first.to_int64()
  let mut content = rest
  if length >= 128 {
    let count = first.to_int() - 128
    guard count > 0 &&
      count <= 4 &&
      count <= rest.length() &&
      rest[0] != b'\x00' else {
      raise InvalidKey("invalid DER length")
    }
    length = 0
    for byte in rest[:count] {
      length = (length << 8) | byte.to_int64()
    }
    guard length >= 128 else { raise InvalidKey("non-minimal DER length") }
    content = rest[count:]
  }
  guard length <= content.length().to_int64() else {
    raise InvalidKey("truncated DER field")
  }
  let end = length.to_int()
  (content[:end], content[end:])
}

///|
fn only_field(input : BytesView, tag : Byte) -> BytesView raise InvalidKey {
  let (value, rest) = take_field(input, tag)
  guard rest.is_empty() else { raise InvalidKey("trailing DER data") }
  value
}

///|
/// DER INTEGER uses the shortest signed two's-complement representation.
fn integer(input : BytesView) -> @bigint.BigInt raise InvalidKey {
  guard input is [first, .. rest] else { raise InvalidKey("empty DER integer") }
  if rest is [next, ..] &&
    (
      (first == b'\x00' && next < b'\x80') ||
      (first == b'\xff' && next >= b'\x80')
    ) {
    raise InvalidKey("non-minimal DER integer")
  }
  if first < b'\x80' {
    @bigint.BigInt::from_octets(input)
  } else {
    // Complement the octets first so even a long input needs no bit-count shift.
    let complement = Bytes::makei(input.length(), i => input[i].lnot())
    -@bigint.BigInt::from_octets(complement[:]) - 1
  }
}
