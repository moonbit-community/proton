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
fn decode_config_string(value : String) -> String {
  let builder = StringBuilder::new()
  let mut escaped = false
  for _, ch in value {
    if escaped {
      match ch {
        '"' => builder.write_char('"')
        '\\' => builder.write_char('\\')
        'n' => builder.write_char('\n')
        't' => builder.write_char('\t')
        _ => {
          builder.write_char('\\')
          builder.write_char(ch)
        }
      }
      escaped = false
    } else if ch == '\\' {
      escaped = true
    } else {
      builder.write_char(ch)
    }
  }
  if escaped {
    builder.write_char('\\')
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
