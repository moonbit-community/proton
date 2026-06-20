///|
fn percent_encode_query_value(value : String) -> String {
  let builder = StringBuilder::new(size_hint=value.length())
  for _, ch in value {
    if is_query_unreserved(ch) {
      builder.write_char(ch)
    } else if ch.to_int() <= 0x7f {
      write_percent_byte(builder, ch.to_int())
    } else {
      // token 在配置校验阶段已经收紧为 ASCII；这里保留兜底行为。
      builder.write_char(ch)
    }
  }
  builder.to_string()
}

///|
fn percent_decode_query_value(value : String) -> String? {
  let builder = StringBuilder::new(size_hint=value.length())
  let mut index = 0
  while index < value.length() {
    if value[index] == ('%' : UInt16) {
      guard index + 2 < value.length() else { return None }
      let hi = hex_value(value[index + 1])
      let lo = hex_value(value[index + 2])
      guard hi is Some(hi) && lo is Some(lo) else { return None }
      builder.write_char((hi * 16 + lo).unsafe_to_char())
      index = index + 3
    } else {
      match value[index].to_char() {
        Some(ch) => builder.write_char(ch)
        None => return None
      }
      index = index + 1
    }
  }
  Some(builder.to_string())
}

///|
fn is_query_unreserved(ch : Char) -> Bool {
  ch.is_ascii_alphabetic() ||
  ch.is_ascii_digit() ||
  ch == '-' ||
  ch == '_' ||
  ch == '.' ||
  ch == '~'
}

///|
fn write_percent_byte(builder : StringBuilder, value : Int) -> Unit {
  let alphabet = "0123456789ABCDEF"
  builder.write_char('%')
  builder.write_char(alphabet.get_char(value / 16).unwrap())
  builder.write_char(alphabet.get_char(value % 16).unwrap())
}

///|
fn hex_value(code : UInt16) -> Int? {
  if code >= ('0' : UInt16) && code <= ('9' : UInt16) {
    Some(code.to_int() - ('0' : UInt16).to_int())
  } else if code >= ('a' : UInt16) && code <= ('f' : UInt16) {
    Some(code.to_int() - ('a' : UInt16).to_int() + 10)
  } else if code >= ('A' : UInt16) && code <= ('F' : UInt16) {
    Some(code.to_int() - ('A' : UInt16).to_int() + 10)
  } else {
    None
  }
}
