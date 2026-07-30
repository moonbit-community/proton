///|
priv struct Parser {
  tokens : Triples
  reports : Array[Report]
  mut next : Int
  mut parsed_position : Position
}

///|
let dummy_position : Position = Position::{
  fname: "",
  lnum: 1,
  bol: 0,
  cnum: 0,
}

///|
fn parse_config_document(
  name : String,
  source : String,
) -> (Ast, Array[@basic.Report]) {
  let lex_result = @lexer.tokens_from_string(source, comment=false, name~)
  let reports : Array[Report] = []
  for error in lex_result.errors {
    let (start, end, err) = error
    reports.push(Report::{ loc: Location::{ start, end }, msg: err.to_string() })
  }
  let parser = Parser::{
    tokens: lex_result.tokens,
    reports,
    next: 0,
    parsed_position: first_position(lex_result.tokens),
  }
  let start = parser.peek_spos()
  parser.parsed_position = start
  let fields = parser.parse_top_fields()
  let loc = Location::{ start, end: parser.parsed_position }
  (Ast::Obj(fields, loc), parser.reports)
}

///|
fn first_position(tokens : Triples) -> Position {
  match tokens.get(0) {
    Some((_, start, _)) => start
    None => dummy_position
  }
}

///|
fn is_layout(token : Token) -> Bool {
  match token {
    NEWLINE | COMMENT(_) | SEMI(_) => true
    _ => false
  }
}

///|
fn Parser::peek(self : Parser, nth? : Int = 0) -> Triple {
  let mut offset = 0
  let mut step = 0
  while self.tokens.get(self.next + offset) is Some((token, _, _) as triple) {
    if is_layout(token) {
      offset += 1
      continue
    }
    if step == nth {
      return triple
    }
    step += 1
    offset += 1
  }
  match self.tokens.last() {
    Some(last) => last
    None => (EOF, dummy_position, dummy_position)
  }
}

///|
fn Parser::consume(self : Parser) -> Triple {
  while self.tokens.get(self.next) is Some((token, _, _) as triple) {
    self.next += 1
    if is_layout(token) {
      continue
    }
    self.parsed_position = triple.2
    return triple
  }
  (EOF, dummy_position, dummy_position)
}

///|
fn Parser::skip(self : Parser) -> Unit {
  ignore(self.consume())
}

///|
fn Parser::peek_token(self : Parser, nth? : Int = 0) -> Token {
  self.peek(nth~).0
}

///|
fn Parser::peek_kind(self : Parser, nth? : Int = 0) -> TokenKind {
  self.peek(nth~).0.kind()
}

///|
fn Parser::peek_spos(self : Parser, nth? : Int = 0) -> Position {
  self.peek(nth~).1
}

///|
fn Parser::peek_location(self : Parser) -> Location {
  let (_, start, end) = self.peek()
  Location::{ start, end }
}

///|
fn Parser::loc_start_with(self : Parser, start : Position) -> Location {
  Location::{ start, end: self.parsed_position }
}

///|
fn Parser::consume_if(self : Parser, expected : TokenKind) -> Bool {
  if self.peek_kind() == expected {
    self.skip()
    true
  } else {
    false
  }
}

///|
fn Parser::report_here(self : Parser, msg : String) -> Unit {
  self.reports.push(Report::{ loc: self.peek_location(), msg })
}

///|
fn Parser::parse_top_fields(self : Parser) -> Array[ConfigField] {
  let fields : Array[ConfigField] = []
  while self.peek_kind() != TK_EOF {
    let before = self.next
    match self.parse_identifier() {
      None => {
        self.report_here("expected field name")
        if self.peek_kind() != TK_EOF {
          self.skip()
        }
      }
      Some((key, key_loc)) => {
        if !self.consume_if(TK_EQUAL) {
          self.report_here("expected `=` after field name")
        }
        let value = self.parse_value()
        fields.push(ConfigField::{ key, key_loc, value })
      }
    }
    if self.next == before && self.peek_kind() != TK_EOF {
      self.skip()
    }
  }
  fields
}

///|
fn Parser::parse_object_fields(self : Parser) -> Array[ConfigField] {
  let fields : Array[ConfigField] = []
  if self.consume_if(TK_RBRACE) {
    return fields
  }
  while self.peek_kind() != TK_EOF {
    match self.parse_identifier() {
      None => {
        self.report_here("expected object field name")
        if self.peek_kind() != TK_EOF {
          self.skip()
        }
      }
      Some((key, key_loc)) => {
        if !self.consume_if(TK_COLON) {
          self.report_here("expected `:` after object field name")
        }
        let value = self.parse_value()
        fields.push(ConfigField::{ key, key_loc, value })
        if self.consume_if(TK_RBRACE) {
          return fields
        }
        if self.consume_if(TK_COMMA) {
          if self.consume_if(TK_RBRACE) {
            return fields
          }
        } else if self.peek_kind() != TK_EOF {
          self.report_here("expected `,` or `}` after object field")
        }
      }
    }
  }
  self.report_here("unterminated object")
  fields
}

///|
fn Parser::parse_array_items(self : Parser) -> Array[Ast] {
  let items : Array[Ast] = []
  if self.consume_if(TK_RBRACKET) {
    return items
  }
  while self.peek_kind() != TK_EOF {
    items.push(self.parse_value())
    if self.consume_if(TK_RBRACKET) {
      return items
    }
    if self.consume_if(TK_COMMA) {
      if self.consume_if(TK_RBRACKET) {
        return items
      }
    } else if self.peek_kind() != TK_EOF {
      self.report_here("expected `,` or `]` after array item")
    }
  }
  self.report_here("unterminated array")
  items
}

///|
fn Parser::parse_value(self : Parser) -> Ast {
  let loc = self.peek_location()
  match self.peek_token() {
    TRUE => {
      self.skip()
      Ast::Bool(true, loc)
    }
    FALSE => {
      self.skip()
      Ast::Bool(false, loc)
    }
    STRING(value) => {
      self.skip()
      Ast::Str(decode_config_string(value), loc)
    }
    MULTILINE_STRING(value) => {
      self.skip()
      Ast::Str(value, loc)
    }
    INT(value) => {
      self.skip()
      Ast::Int(value, loc)
    }
    MINUS => self.parse_negative_int()
    LBRACE => {
      let start = self.peek_spos()
      self.skip()
      let fields = self.parse_object_fields()
      Ast::Obj(fields, self.loc_start_with(start))
    }
    LBRACKET => {
      let start = self.peek_spos()
      self.skip()
      let items = self.parse_array_items()
      Ast::Arr(items, self.loc_start_with(start))
    }
    LIDENT(word) => {
      self.skip()
      self.reports.push(Report::{ loc, msg: "unsupported value: " + word })
      Ast::Str(word, loc)
    }
    FLOAT(_) | DOUBLE(_) as token => {
      self.skip()
      self.reports.push(Report::{
        loc,
        msg: "unsupported value: " + token.to_expect_string(),
      })
      Ast::Str("", loc)
    }
    EOF => {
      self.report_here("expected value")
      Ast::Str("", loc)
    }
    _ => {
      self.report_here("expected value")
      if self.peek_kind() != TK_EOF {
        self.skip()
      }
      Ast::Str("", loc)
    }
  }
}

///|
fn hex_digit_value(ch : Char) -> Int {
  if ch >= '0' && ch <= '9' {
    ch.to_int() - '0'.to_int()
  } else if ch >= 'a' && ch <= 'f' {
    ch.to_int() - 'a'.to_int() + 10
  } else if ch >= 'A' && ch <= 'F' {
    ch.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
fn octal_digit_value(ch : Char) -> Int {
  if ch >= '0' && ch <= '7' {
    ch.to_int() - '0'.to_int()
  } else {
    -1
  }
}

///|
/// Decodes every escape sequence the MoonBit string lexer accepts in config
/// strings: the simple escapes plus `\xHH`, `\oOOO`, `\uHHHH` (including
/// surrogate pairs) and `\u{...}`. Values that are not valid Unicode scalar
/// values degrade to U+FFFD; malformed tails are preserved verbatim (the
/// lexer only emits valid escapes, so those paths are defensive).
fn decode_config_string(value : String) -> String {
  let chars = value.to_array()
  let len = chars.length()
  let builder = StringBuilder::new()
  let replacement = '\u{FFFD}'
  let mut i = 0
  while i < len {
    let ch = chars[i]
    if ch != '\\' {
      builder.write_char(ch)
      i += 1
      continue
    }
    if i + 1 >= len {
      builder.write_char('\\')
      break
    }
    let esc = chars[i + 1]
    match esc {
      '"' | '\\' | '\'' | '`' | '/' | ' ' => {
        builder.write_char(esc)
        i += 2
      }
      'n' => {
        builder.write_char('\n')
        i += 2
      }
      't' => {
        builder.write_char('\t')
        i += 2
      }
      'b' => {
        builder.write_char('\b')
        i += 2
      }
      'r' => {
        builder.write_char('\r')
        i += 2
      }
      'f' => {
        builder.write_char('\f')
        i += 2
      }
      'x' => {
        if i + 3 < len {
          let hi = hex_digit_value(chars[i + 2])
          let lo = hex_digit_value(chars[i + 3])
          if hi >= 0 && lo >= 0 {
            builder.write_char((hi * 16 + lo).unsafe_to_char())
            i += 4
            continue
          }
        }
        builder.write_char('\\')
        builder.write_char(esc)
        i += 2
      }
      'o' => {
        if i + 4 < len {
          let a = octal_digit_value(chars[i + 2])
          let b = octal_digit_value(chars[i + 3])
          let c = octal_digit_value(chars[i + 4])
          // The string lexer restricts octal escapes to \o[0-3][0-7]{2}.
          if a >= 0 && a <= 3 && b >= 0 && c >= 0 {
            builder.write_char((a * 64 + b * 8 + c).unsafe_to_char())
            i += 5
            continue
          }
        }
        builder.write_char('\\')
        builder.write_char(esc)
        i += 2
      }
      'u' =>
        if i + 2 < len && chars[i + 2] == '{' {
          let mut j = i + 3
          let mut cp = 0
          let mut digits = 0
          let mut overflow = false
          while j < len && chars[j] != '}' {
            let digit = hex_digit_value(chars[j])
            if digit < 0 {
              break
            }
            if cp > 0x10FFFF {
              overflow = true
            } else {
              cp = cp * 16 + digit
            }
            digits += 1
            j += 1
          }
          if j < len && chars[j] == '}' && digits > 0 {
            if overflow || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) {
              builder.write_char(replacement)
            } else {
              builder.write_char(cp.unsafe_to_char())
            }
            i = j + 1
            continue
          }
          builder.write_char('\\')
          builder.write_char(esc)
          i += 2
        } else if i + 5 < len {
          let h0 = hex_digit_value(chars[i + 2])
          let h1 = hex_digit_value(chars[i + 3])
          let h2 = hex_digit_value(chars[i + 4])
          let h3 = hex_digit_value(chars[i + 5])
          if h0 >= 0 && h1 >= 0 && h2 >= 0 && h3 >= 0 {
            let cp = ((h0 * 16 + h1) * 16 + h2) * 16 + h3
            if cp >= 0xD800 && cp <= 0xDBFF {
              // High surrogate: combine with a following \uDC00-\uDFFF escape.
              let mut combined = false
              if i + 11 < len && chars[i + 6] == '\\' && chars[i + 7] == 'u' {
                let l0 = hex_digit_value(chars[i + 8])
                let l1 = hex_digit_value(chars[i + 9])
                let l2 = hex_digit_value(chars[i + 10])
                let l3 = hex_digit_value(chars[i + 11])
                if l0 >= 0 && l1 >= 0 && l2 >= 0 && l3 >= 0 {
                  let lo = ((l0 * 16 + l1) * 16 + l2) * 16 + l3
                  if lo >= 0xDC00 && lo <= 0xDFFF {
                    builder.write_char(
                      (0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)).unsafe_to_char(),
                    )
                    combined = true
                    i += 12
                  }
                }
              }
              if !combined {
                builder.write_char(replacement)
                i += 6
              }
            } else if cp >= 0xDC00 && cp <= 0xDFFF {
              builder.write_char(replacement)
              i += 6
            } else {
              builder.write_char(cp.unsafe_to_char())
              i += 6
            }
            continue
          }
          builder.write_char('\\')
          builder.write_char(esc)
          i += 2
        } else {
          builder.write_char('\\')
          builder.write_char(esc)
          i += 2
        }
      _ => {
        builder.write_char('\\')
        builder.write_char(esc)
        i += 2
      }
    }
  }
  builder.to_string()
}

///|
fn Parser::parse_negative_int(self : Parser) -> Ast {
  let start = self.peek_spos()
  self.skip()
  match self.peek_token() {
    INT(value) => {
      self.skip()
      Ast::Int("-" + value, self.loc_start_with(start))
    }
    _ => {
      self.report_here("expected digits after `-`")
      Ast::Int("-", self.loc_start_with(start))
    }
  }
}

///|
fn Parser::parse_identifier(self : Parser) -> (String, ConfigLoc)? {
  let loc = self.peek_location()
  match self.peek_token() {
    LIDENT(name) => {
      self.skip()
      Some((name, loc))
    }
    PACKAGE => {
      self.skip()
      Some(("package", loc))
    }
    _ => None
  }
}
