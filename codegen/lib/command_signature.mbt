///|
/// Reads only annotated command signatures. The MoonBit compiler validates the
/// complete source; bodies and unrelated declarations are opaque to codegen.
fn parse_typed_commands(
  tokens : Array[@tokens.Token],
  path : String,
) -> Array[ParsedTypedCommand] raise {
  let commands = []
  let mut contract : String? = None
  let delimiters : Array[@tokens.TokenKind] = []
  let mut i = 0
  while i < tokens.length() {
    let token = tokens[i]
    if delimiters.is_empty() {
      match token {
        ATTRIBUTE(("proton", Some("command"), payload)) => {
          guard contract is None else {
            raise CommandCodegenError::Attribute(
              kind="command",
              detail="only one #proton.command attribute is allowed",
            )
          }
          contract = Some(parse_contract_attribute("#proton.command" + payload))
        }
        ATTRIBUTE(_) | PUB | PRIV | ASYNC | NEWLINE | COMMENT(_) => ()
        FN => {
          if contract is Some(expression) {
            let reader = CommandSignature::{ tokens, index: i + 1, path, }
            commands.push(reader.read_command(expression))
            i = reader.index - 1
          }
          contract = None
        }
        _ => {
          guard contract is None else {
            raise CommandCodegenError::Attribute(
              kind="command",
              detail="#proton.command must annotate a function",
            )
          }
        }
      }
    }
    match token {
      LBRACE => delimiters.push(@tokens.TokenKind::TK_RBRACE)
      LPAREN | DOT_LPAREN => delimiters.push(@tokens.TokenKind::TK_RPAREN)
      LBRACKET => delimiters.push(@tokens.TokenKind::TK_RBRACKET)
      LBRACKET_BAR => delimiters.push(@tokens.TokenKind::TK_BAR_RBRACKET)
      RBRACE | RPAREN | RBRACKET | BAR_RBRACKET => {
        guard delimiters.pop() is Some(expected) && expected == token.kind() else {
          raise CodegenInputError::SourceParse(path~)
        }
      }
      _ => ()
    }
    i += 1
  }
  guard delimiters.is_empty() && contract is None else {
    raise CodegenInputError::SourceParse(path~)
  }
  commands
}

///|
priv struct CommandSignature {
  tokens : Array[@tokens.Token]
  mut index : Int
  path : String
}

///|
fn CommandSignature::peek(self : CommandSignature) -> @tokens.Token {
  while self.index < self.tokens.length() {
    match self.tokens[self.index] {
      NEWLINE | COMMENT(_) => self.index += 1
      token => return token
    }
  }
  @tokens.Token::EOF
}

///|
fn CommandSignature::take(self : CommandSignature) -> @tokens.Token {
  let token = self.peek()
  self.index += 1
  token
}

///|
fn CommandSignature::expect(
  self : CommandSignature,
  kind : @tokens.TokenKind,
) -> Unit raise {
  guard self.take().kind() == kind else {
    raise CodegenInputError::SourceParse(path=self.path)
  }
}

///|
fn CommandSignature::read_command(
  self : CommandSignature,
  contract : String,
) -> ParsedTypedCommand raise {
  // Generic binders precede the function name. They are checked by MoonBit.
  if self.peek() is LBRACKET {
    ignore(self.take())
    let mut depth = 1
    while depth > 0 {
      match self.take() {
        LBRACKET => depth += 1
        RBRACKET => depth -= 1
        EOF => raise CodegenInputError::SourceParse(path=self.path)
        _ => ()
      }
    }
  }
  let (receiver, name) = match self.take() {
    LIDENT(name) => (None, name)
    UIDENT(receiver) => {
      self.expect(@tokens.TokenKind::TK_COLONCOLON)
      guard self.take() is LIDENT(name) else {
        raise CodegenInputError::SourceParse(path=self.path)
      }
      (Some(receiver), name)
    }
    PACKAGE_NAME(pkg) => {
      guard self.take() is DOT_UIDENT(receiver) else {
        raise CodegenInputError::SourceParse(path=self.path)
      }
      self.expect(@tokens.TokenKind::TK_COLONCOLON)
      guard self.take() is LIDENT(name) else {
        raise CodegenInputError::SourceParse(path=self.path)
      }
      (Some("@" + pkg + "." + receiver), name)
    }
    _ => raise CodegenInputError::SourceParse(path=self.path)
  }
  self.expect(@tokens.TokenKind::TK_LPAREN)
  let params = []
  while !(self.peek() is RPAREN) {
    let param = match self.take() {
      LIDENT(param) => param
      POST_LABEL(_) | POST_LABEL_TRANSPARENT(_) =>
        raise CommandCodegenError::Command(
          function_name=name,
          detail="labeled and optional parameters are not supported",
        )
      UNDERSCORE =>
        raise CommandCodegenError::Command(
          function_name=name,
          detail="discard parameters are not supported",
        )
      _ => raise CodegenInputError::SourceParse(path=self.path)
    }
    if self.peek() is QUESTION {
      raise CommandCodegenError::Command(
        function_name=name,
        detail="labeled and optional parameters are not supported",
      )
    }
    guard self.take() is COLON else {
      raise CommandCodegenError::Command(
        function_name=name,
        detail="parameters must use `name : Type`",
      )
    }
    params.push(
      (param, self.read_type("command parameter " + name + "." + param)),
    )
    match self.peek() {
      COMMA => ignore(self.take())
      RPAREN => break
      _ =>
        raise CommandCodegenError::UnsupportedType(
          context="command parameter " + name + "." + param,
        )
    }
  }
  self.expect(@tokens.TokenKind::TK_RPAREN)
  make_typed_command(name, receiver, params, contract)
}

///|
fn CommandSignature::read_type(
  self : CommandSignature,
  context : String,
) -> String raise {
  let mut result = match self.take() {
    UIDENT(name) => name
    PACKAGE_NAME(pkg) => {
      guard self.take() is DOT_UIDENT(name) else {
        raise CommandCodegenError::UnsupportedType(context~)
      }
      "@" + pkg + "." + name
    }
    LPAREN => {
      let parts = self.read_types(@tokens.TokenKind::TK_RPAREN, context)
      "(" + parts.join(", ") + ")"
    }
    _ => raise CommandCodegenError::UnsupportedType(context~)
  }
  if self.peek() is LBRACKET {
    ignore(self.take())
    result += "[" +
      self.read_types(@tokens.TokenKind::TK_RBRACKET, context).join(", ") +
      "]"
  }
  while self.peek() is QUESTION {
    ignore(self.take())
    result += "?"
  }
  result
}

///|
fn CommandSignature::read_types(
  self : CommandSignature,
  end : @tokens.TokenKind,
  context : String,
) -> Array[String] raise {
  let parts = []
  while self.peek().kind() != end {
    parts.push(self.read_type(context))
    if self.peek().kind() == end {
      break
    }
    self.expect(@tokens.TokenKind::TK_COMMA)
  }
  self.expect(end)
  parts
}
