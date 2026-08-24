///|
/// Decodes a hexadecimal signature body.
///
/// Surrounding whitespace is tolerated because a signature is usually produced
/// by a shell pipeline that appends a newline. Nothing else is: a separator or
/// stray character inside the value means the file is not what the release
/// process intended, and guessing would be worse than refusing.
fn decode_hex_body(body : Bytes, url : String) -> Bytes raise UpdateError {
  decode_hex_body_text(bytes_to_utf8(body), url)
}

///|
fn decode_hex_body_text(text : String, url : String) -> Bytes raise UpdateError {
  let digits : Array[Char] = []
  for character in text {
    if character is (' ' | '\t' | '\r' | '\n') {
      continue
    }
    digits.push(character)
  }
  guard digits.length() > 0 && digits.length() % 2 == 0 else {
    raise MalformedSignature(url~)
  }
  let out : Array[Byte] = []
  for index = 0; index < digits.length(); index = index + 2 {
    let high = hex_digit(digits[index], url)
    let low = hex_digit(digits[index + 1], url)
    out.push((high * 16 + low).to_byte())
  }
  Bytes::from_array(out[:])
}

///|
fn hex_digit(digit : Char, url : String) -> Int raise UpdateError {
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
  raise MalformedSignature(url~)
}

///|
/// Interprets a fetched body as text.
///
/// A body that is not valid UTF-8 yields replacement characters rather than an
/// error. It will fail the signature check or the manifest parse a moment
/// later, and those refusals describe the problem better than an encoding
/// complaint would.
fn bytes_to_utf8(body : Bytes) -> String {
  let builder = StringBuilder(size_hint=body.length())
  for character in @encoding.decoder(UTF8).decode_lossy(body[:]) {
    builder.write_char(character)
  }
  builder.to_string()
}
