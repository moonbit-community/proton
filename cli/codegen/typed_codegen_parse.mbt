///|
/// Generates one typed package registrar from explicit MoonBit source inputs.
pub fn generate_typed_commands_from_sources(
  sources : Array[(String, String)],
  extension_identity? : (String, String)? = None,
) -> ProtonCommandCodegenOutput raise {
  guard sources.length() > 0 else {
    raise CodegenInputError::PackageRead(
      path="<inputs>",
      detail="at least one MoonBit source file is required",
    )
  }
  let commands : Array[ParsedTypedCommand] = []
  for source_entry in sources {
    let (path, source) = source_entry
    let (ast, reports) = @parser.parse_string(source)
    guard reports.is_empty() else {
      raise CodegenInputError::SourceParse(path~)
    }
    commands.append(parse_typed_commands(ast, source))
  }
  guard commands.length() > 0 else { raise CommandCodegenError::MissingCommand }
  validate_typed_contract_duplicates(commands)
  render_typed_command_registrar(ParsedTypedModule::{
    commands,
    extension_identity,
  })
}

///|
/// Generates one typed package registrar from explicit source files.
///
/// Every input must belong to the same package directory. If that directory
/// contains `moon.ext`, its identity is emitted as ordinary MoonBit contract
/// source beside the registrar.
pub async fn generate_typed_commands_from_files(
  input_files : Array[String],
) -> ProtonCommandCodegenOutput {
  guard input_files.length() > 0 else {
    raise CodegenInputError::PackageRead(
      path="<inputs>",
      detail="at least one MoonBit source file is required",
    )
  }
  let package_dir = path_dirname(input_files[0])
  let sources : Array[(String, String)] = []
  for input_file in input_files {
    guard path_dirname(input_file) == package_dir else {
      raise CodegenInputError::PackageRead(
        path=input_file,
        detail="all codegen inputs must belong to the same package directory",
      )
    }
    let source = @async_fs.read_file(input_file).text() catch {
      error =>
        raise CodegenInputError::InputRead(
          path=input_file,
          detail=@debug.render(@debug.to_repr(error)),
        )
    }
    sources.push((input_file, source))
  }
  let metadata_path = path_join(package_dir, "moon.ext")
  let extension_identity = if (@async_fs.exists(metadata_path) catch {
      _ => false
    }) {
    Some(read_moon_ext_identity(metadata_path))
  } else {
    None
  }
  generate_typed_commands_from_sources(sources, extension_identity~)
}

///|
/// Selects typed registrar generation when a contract-bound command appears.
///
/// The legacy branch is temporary while built-in extensions are migrated in
/// this pull request; it is removed with the old annotation model.
pub async fn generate_commands_from_files(
  input_files : Array[String],
) -> ProtonCommandCodegenOutput {
  guard input_files.length() > 0 else {
    raise CodegenInputError::PackageRead(
      path="<inputs>",
      detail="at least one MoonBit source file is required",
    )
  }
  let mut typed = false
  for input_file in input_files {
    let source = @async_fs.read_file(input_file).text() catch {
      error =>
        raise CodegenInputError::InputRead(
          path=input_file,
          detail=@debug.render(@debug.to_repr(error)),
        )
    }
    if source.contains("#proton.command(contract") {
      typed = true
    }
  }
  if typed {
    generate_typed_commands_from_files(input_files)
  } else {
    guard input_files.length() == 1 else {
      raise CodegenInputError::PackageRead(
        path="<inputs>",
        detail="legacy command generation accepts exactly one input file",
      )
    }
    generate_app_commands_from_file_with_metadata(input_files[0])
  }
}

///|
fn parse_typed_commands(
  ast : @list.List[@moonbitlang/parser/syntax.Impl],
  source : String,
) -> Array[ParsedTypedCommand] raise {
  let commands : Array[ParsedTypedCommand] = []
  ast.each(fn(item) raise {
    match item {
      TopFuncDef(fun_decl~, ..) =>
        match typed_contract_attribute(fun_decl.attrs, source) {
          Some(contract_expression) =>
            commands.push(
              parse_typed_command_from_func(fun_decl, contract_expression),
            )
          None => ()
        }
      TopTypeDef(type_decl) =>
        reject_removed_typed_attributes(type_decl.attrs, source)
      _ => ()
    }
  })
  commands
}

///|
fn typed_contract_attribute(
  attrs : @list.List[@moonbitlang/parser/attribute.Attribute],
  source : String,
) -> String? raise {
  let mut contract : String? = None
  attrs.each(fn(attr) raise {
    let raw = recover_attr_raw(source, attr)
    if raw.has_prefix("#proton.command") {
      guard contract is None else {
        raise CommandCodegenError::Attribute(
          kind="command",
          detail="only one #proton.command attribute is allowed",
        )
      }
      contract = Some(parse_contract_attribute(raw))
    } else if raw.has_prefix("#proton.event") {
      raise CommandCodegenError::Attribute(
        kind="event",
        detail="#proton.event was removed; declare an Event value in the shared contract",
      )
    } else if raw.has_prefix("#proton.script") ||
      raw.has_prefix("#proton.destroy") {
      raise CommandCodegenError::Attribute(
        kind="attribute",
        detail="#proton.script and #proton.destroy are extension lifecycle configuration, not command bindings",
      )
    }
  })
  contract
}

///|
fn reject_removed_typed_attributes(
  attrs : @list.List[@moonbitlang/parser/attribute.Attribute],
  source : String,
) -> Unit raise {
  attrs.each(fn(attr) raise {
    let raw = recover_attr_raw(source, attr)
    if raw.has_prefix("#proton.event") {
      raise CommandCodegenError::Attribute(
        kind="event",
        detail="#proton.event was removed; declare an Event value in the shared contract",
      )
    }
  })
}

///|
fn parse_contract_attribute(raw : String) -> String raise {
  let prefix = "#proton.command"
  guard raw.has_prefix(prefix + "(") && raw.has_suffix(")") else {
    raise CommandCodegenError::Attribute(
      kind="command",
      detail="expected #proton.command(contract=<descriptor>)",
    )
  }
  let inner = raw
    .unsafe_substring(start=prefix.length() + 1, end=raw.length() - 1)
    .trim()
    .to_owned()
  let (label, expression) = match inner.split_once("=") {
    Some(parts) => (parts.0.trim().to_owned(), parts.1.trim().to_owned())
    None =>
      raise CommandCodegenError::Attribute(
        kind="command",
        detail="expected a contract argument",
      )
  }
  guard label == "contract" else {
    raise CommandCodegenError::Attribute(
      kind="command",
      detail="only the contract argument is supported",
    )
  }
  validate_contract_expression(expression)
  expression
}

///|
fn validate_contract_expression(expression : String) -> Unit raise {
  guard expression != "" else {
    raise CommandCodegenError::Attribute(
      kind="command",
      detail="contract expression must not be empty",
    )
  }
  guard !expression.has_prefix("@") else {
    raise CommandCodegenError::Attribute(
      kind="command",
      detail="contract must be a local typed alias because MoonBit attributes cannot contain package-qualified values",
    )
  }
  for _, ch in expression {
    let valid = is_identifier_continue_char(ch) || ch == '.'
    guard valid else {
      raise CommandCodegenError::Attribute(
        kind="command",
        detail="contract must be a stable MoonBit value reference",
      )
    }
  }
  guard !expression.has_suffix(".") else {
    raise CommandCodegenError::Attribute(
      kind="command",
      detail="contract must be a stable MoonBit value reference",
    )
  }
}

///|
fn parse_typed_command_from_func(
  func : @moonbitlang/parser/syntax.FunDecl,
  contract_expression : String,
) -> ParsedTypedCommand raise {
  let function_name = func.name.name
  validate_identifier("command function name", function_name)
  let receiver_type = match func.type_name {
    Some(type_name) => {
      guard !type_name.is_object else {
        raise CommandCodegenError::Command(
          function_name~,
          detail="object receiver methods are not supported",
        )
      }
      Some(long_ident_text(type_name.name))
    }
    None => None
  }
  let params = match func.decl_params {
    Some(params) => parse_typed_params(function_name, params)
    None => []
  }
  let first_handler_param = match receiver_type {
    Some(receiver) => {
      guard params.length() > 0 &&
        params[0].0 == "self" &&
        params[0].1 == receiver else {
        raise CommandCodegenError::Command(
          function_name~,
          detail="receiver commands must begin with `self : " + receiver + "`",
        )
      }
      1
    }
    None => 0
  }
  let handler_params = params[first_handler_param:]
  let accepts_context = handler_params.length() > 0 &&
    handler_params[0].0 == "context" &&
    (
      handler_params[0].1 == "@proton.CommandContext" ||
      handler_params[0].1 == "@proton_command.CommandContext"
    )
  let request_index = if accepts_context { 1 } else { 0 }
  guard handler_params.length() - request_index <= 1 else {
    raise CommandCodegenError::Command(
      function_name~,
      detail="typed commands accept one request value and an optional leading CommandContext",
    )
  }
  if !accepts_context {
    for parameter in handler_params {
      let (name, param_type) = parameter
      guard name != "context" else {
        raise CommandCodegenError::Command(
          function_name~,
          detail="context must use type @proton.CommandContext",
        )
      }
      ignore(param_type)
    }
  }
  ParsedTypedCommand::{
    function_name,
    receiver_type,
    contract_expression,
    accepts_context,
    has_request: handler_params.length() > request_index,
  }
}

///|
fn parse_typed_params(
  function_name : String,
  params : @list.List[@moonbitlang/parser/syntax.Parameter],
) -> Array[(String, String)] raise {
  let parsed : Array[(String, String)] = []
  params.each(fn(param) raise {
    match param {
      Positional(binder={ name, .. }, ty=Some(ty)) =>
        parsed.push(
          (
            name,
            type_expr_text(
              ty,
              context="command parameter " + function_name + "." + name,
            ),
          ),
        )
      DiscardPositional(..) =>
        raise CommandCodegenError::Command(
          function_name~,
          detail="discard parameters are not supported",
        )
      Labelled(..) =>
        raise CommandCodegenError::Command(
          function_name~,
          detail="labeled and optional parameters are not supported",
        )
      _ =>
        raise CommandCodegenError::Command(
          function_name~,
          detail="parameters must use `name : Type`",
        )
    }
  })
  parsed
}

///|
fn validate_typed_contract_duplicates(
  commands : Array[ParsedTypedCommand],
) -> Unit raise {
  let contracts : Map[String, Bool] = Map([])
  for command in commands {
    guard contracts.get(command.contract_expression) is None else {
      raise CommandCodegenError::Duplicate(
        kind="command contract",
        name=command.contract_expression,
      )
    }
    contracts[command.contract_expression] = true
  }
}
