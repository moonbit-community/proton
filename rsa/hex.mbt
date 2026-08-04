///|
/// Decodes a strict lowercase-or-uppercase hexadecimal string into bytes.
///
/// Strict means: an even number of digits, every digit in `[0-9a-fA-F]`, and no
/// whitespace, separators, or prefix. Key material is written once and read by
/// a security check, so a lenient decoder would only widen the set of inputs
/// that silently decode to something other than what the author wrote.
fn decode_hex(text : String) -> Bytes raise KeyError {
  let digits = text.to_array()
  guard digits.length() % 2 == 0 else {
    raise Malformed(detail="hexadecimal length must be even")
  }
  guard digits.length() > 0 else {
    raise Malformed(detail="hexadecimal value is empty")
  }
  let out : Array[Byte] = []
  for index = 0; index < digits.length(); index = index + 2 {
    let high = hex_digit_value(digits[index])
    let low = hex_digit_value(digits[index + 1])
    out.push((high * 16 + low).to_byte())
  }
  Bytes::from_array(out[:])
}

///|
fn hex_digit_value(digit : Char) -> Int raise KeyError {
  let code = digit.to_int()
  if code >= '0'.to_int() && code <= '9'.to_int() {
    return code - '0'.to_int()
  }
  if code >= 'a'.to_int() && code <= 'f'.to_int() {
    return code - 'a'.to_int() + 10
  }
  if code >= 'A'.to_int() && code <= 'F'.to_int() {
    return code - 'A'.to_int() + 10
  }
  raise Malformed(detail="not a hexadecimal digit: \{digit}")
}
