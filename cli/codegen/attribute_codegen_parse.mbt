///|
/// Generates Proton command extension MoonBit source from one source string.
///
/// This entry point parses only `source`; it is intended for unit tests and
/// callers that already have the full package context in memory.
pub fn generate_app_commands_from_source(
  source : String,
  extension_id : String,
  js_namespace : String,
) -> ProtonCommandCodegenOutput raise {
  validate_non_empty("extension id", extension_id)
  validate_js_part("extension namespace", js_namespace)
  let (ast, reports) = @parser.parse_string(source)
  guard reports.is_empty() else {
    raise CodegenInputError::SourceParse(path="<memory>")
  }
  let base = parse_proton_ast(ast, source)
  let parsed = ParsedProtonModule::{
    commands: base.commands,
    events: base.events,
    scripts: base.scripts,
    destroy: base.destroy,
    package_commands: [],
    package_events: [],
  }
  validate_parsed_module(parsed)
  render_proton_command_codegen(parsed, extension_id, js_namespace)
}

///|
/// Generates Proton command extension MoonBit source from one input file.
///
/// The input file's package directory is scanned for ordinary `.mbt` files so
/// duplicate command and event names can be checked against sibling sources.
pub fn generate_app_commands_from_file(
  input_file : String,
  extension_id : String,
  js_namespace : String,
) -> ProtonCommandCodegenOutput raise {
  validate_extension_id(extension_id)
  validate_js_part("extension namespace", js_namespace)
  let parsed = collect_package_proton_module(input_file)
  validate_parsed_module(parsed)
  render_proton_command_codegen(parsed, extension_id, js_namespace)
}

///|
/// Generates Proton command extension MoonBit source using extension metadata.
///
/// The codegen input's package directory must contain `moon.ext` with string
/// `id` and `namespace` fields.
pub fn generate_app_commands_from_file_with_metadata(
  input_file : String,
) -> ProtonCommandCodegenOutput raise {
  let (extension_id, js_namespace) = read_package_extension_config(input_file)
  generate_app_commands_from_file(input_file, extension_id, js_namespace)
}

///|
fn read_package_extension_config(input_file : String) -> (String, String) raise {
  let package_dir = path_dirname(input_file)
  let moon_ext_path = path_join(package_dir, "moon.ext")
  guard @mbfs.path_exists(moon_ext_path) else {
    raise CodegenMetadataFileError::MissingMetadata(path=moon_ext_path)
  }
  let has_moon_ext = @mbfs.is_file(moon_ext_path) catch {
    error =>
      raise CodegenInputError::InputRead(
        path=moon_ext_path,
        detail=@debug.render(@debug.to_repr(error)),
      )
  }
  guard has_moon_ext else {
    raise CodegenMetadataFileError::MissingMetadata(path=moon_ext_path)
  }
  let (id, js_namespace) = read_moon_ext_codegen_config_file(moon_ext_path)
  validate_extension_id(id)
  validate_js_part("extension namespace", js_namespace)
  (id, js_namespace)
}

///|
fn read_moon_ext_codegen_config_file(path : String) -> (String, String) raise {
  let text = @mbfs.read_file_to_string(path) catch {
    error =>
      raise CodegenInputError::InputRead(
        path~,
        detail=@debug.render(@debug.to_repr(error)),
      )
  }
  read_moon_ext_codegen_config(path, text)
}

///|
/// Validates a `moon.ext` file and returns its extension id and JavaScript namespace.
pub fn read_moon_ext_identity(path : String) -> (String, String) raise {
  read_moon_ext_codegen_config_file(path)
}

///|
fn read_moon_ext_codegen_config(
  path : String,
  text : String,
) -> (String, String) raise {
  let (ast, reports) = @proton_config.parse_moon_ext(name=path, text)
  if reports.length() > 0 {
    raise CodegenMetadataFileError::Syntax(
      path~,
      diagnostics=render_moon_ext_config_reports(reports),
    )
  }
  try {
    match ast {
      Obj(fields, _) => read_moon_ext_codegen_fields(fields)
      _ => raise CodegenMetadataError::InvalidRoot
    }
  } catch {
    error => raise CodegenMetadataFileError::Invalid(path~, error~)
  }
}

///|
fn read_moon_ext_codegen_fields(
  fields : Array[@proton_config.ConfigField],
) -> (String, String) raise CodegenMetadataError {
  validate_moon_ext_codegen_fields(fields)
  (
    moon_ext_codegen_required_string(fields, "id"),
    moon_ext_codegen_required_string(fields, "namespace"),
  )
}

///|
fn validate_moon_ext_codegen_fields(
  fields : Array[@proton_config.ConfigField],
) -> Unit raise CodegenMetadataError {
  let seen : Map[String, Bool] = Map([])
  for field in fields {
    guard !seen.contains(field.key) else {
      raise DuplicateField(field=field.key)
    }
    seen[field.key] = true
    match field.key {
      "id"
      | "namespace"
      | "version"
      | "display_name"
      | "description"
      | "license"
      | "repository"
      | "readme" =>
        match field.value {
          Str(_, _) => ()
          _ => raise InvalidType(field=field.key, expected="a string")
        }
      "package" =>
        match field.value {
          Str(value, _) => validate_npm_package_name(value)
          _ => raise InvalidType(field="package", expected="a string")
        }
      "keywords" | "platforms" | "dependencies" =>
        match field.value {
          Arr(_, _) => ()
          _ => raise InvalidType(field=field.key, expected="an array")
        }
      other => raise UnknownField(field=other)
    }
  }
}

///|
fn moon_ext_codegen_required_string(
  fields : Array[@proton_config.ConfigField],
  key : String,
) -> String raise CodegenMetadataError {
  for field in fields {
    if field.key == key {
      match field.value {
        Str(value, _) => return value
        _ => raise InvalidType(field=key, expected="a string")
      }
    }
  }
  raise MissingField(field=key)
}

///|
fn render_moon_ext_config_reports(reports : Array[@basic.Report]) -> String {
  let builder = StringBuilder::new()
  for index, report in reports {
    if index > 0 {
      builder.write_string("\n")
    }
    builder.write_string(report.to_string())
  }
  builder.to_string()
}

///|
fn collect_package_proton_module(
  input_file : String,
) -> ParsedProtonModule raise {
  let input_path = normalize_path(input_file)
  let dir = path_dirname(input_file)
  let target = ParsedProtonModule::{
    commands: [],
    events: [],
    scripts: [],
    destroy: None,
    package_commands: [],
    package_events: [],
  }
  let context = ParsedProtonModule::{
    commands: [],
    events: [],
    scripts: [],
    destroy: None,
    package_commands: [],
    package_events: [],
  }
  let entries = @mbfs.read_dir(dir) catch {
    error =>
      raise CodegenInputError::PackageRead(
        path=dir,
        detail=@debug.render(@debug.to_repr(error)),
      )
  }
  for entry in entries {
    guard is_codegen_source_file(entry) else { continue }
    let path = path_join(dir, entry)
    let is_file = @mbfs.is_file(path) catch {
      error =>
        raise CodegenInputError::PackageRead(
          path~,
          detail=@debug.render(@debug.to_repr(error)),
        )
    }
    guard is_file else { continue }
    let is_target = normalize_path(path) == input_path ||
      entry == path_basename(input_file)
    let source = @mbfs.read_file_to_string(path) catch {
      error =>
        raise CodegenInputError::InputRead(
          path~,
          detail=@debug.render(@debug.to_repr(error)),
        )
    }
    let (ast, reports) = @parser.parse_string(source)
    if !reports.is_empty() {
      guard !is_target else {
        raise CodegenInputError::SourceParse(path=input_file)
      }
      continue
    }
    let parsed = parse_proton_ast(ast, source)
    if is_target {
      target.commands.append(parsed.commands)
      target.events.append(parsed.events)
      target.scripts.append(parsed.scripts)
      if parsed.destroy is Some(destroy) {
        target.destroy = Some(destroy)
      }
    } else {
      context.commands.append(parsed.commands)
      context.events.append(parsed.events)
    }
  }
  ParsedProtonModule::{
    commands: target.commands,
    events: target.events,
    scripts: target.scripts,
    destroy: target.destroy,
    package_commands: context.commands,
    package_events: context.events,
  }
}

///|
fn is_codegen_source_file(name : String) -> Bool {
  name.has_suffix(".mbt") &&
  !name.has_suffix(".g.mbt") &&
  !name.has_suffix("_test.mbt") &&
  !name.has_suffix("_wbtest.mbt")
}

///|
fn parse_proton_ast(
  ast : @list.List[@moonbitlang/parser/syntax.Impl],
  source : String,
) -> ParsedProtonModule raise {
  let commands : Array[ParsedProtonCommand] = []
  let events : Array[ParsedProtonEvent] = []
  let scripts : Array[ParsedProtonScript] = []
  let mut destroy : ParsedProtonDestroy? = None
  ast.each(fn(item) raise {
    match item {
      TopFuncDef(fun_decl~, ..) =>
        match parse_func_codegen_item(fun_decl, source) {
          FunctionCodegenItem::None => ()
          Command(command) => commands.push(command)
          Script(script) => scripts.push(script)
          Destroy(next_destroy) =>
            match destroy {
              Some(_) =>
                raise CommandCodegenError::Attribute(
                  kind="destroy",
                  detail="only one destroy hook is supported",
                )
              None => destroy = Some(next_destroy)
            }
        }
      TopTypeDef(type_decl) =>
        match parse_event_from_type_def(type_decl, source) {
          Some(event) => events.push(event)
          None => ()
        }
      _ => ()
    }
  })
  ParsedProtonModule::{
    commands,
    events,
    scripts,
    destroy,
    package_commands: [],
    package_events: [],
  }
}

///|
priv enum FunctionCodegenItem {
  None
  Command(ParsedProtonCommand)
  Script(ParsedProtonScript)
  Destroy(ParsedProtonDestroy)
}

///|
fn parse_func_codegen_item(
  func : @moonbitlang/parser/syntax.FunDecl,
  source : String,
) -> FunctionCodegenItem raise {
  let attrs = collect_proton_attributes(func.attrs, source)
  match select_single_proton_attribute(attrs) {
    None => FunctionCodegenItem::None
    Some(attr) =>
      match attr.kind {
        ProtonAttributeKind::Command =>
          FunctionCodegenItem::Command(parse_command_from_func(func, attr))
        ProtonAttributeKind::Script =>
          FunctionCodegenItem::Script(parse_script_from_func(func))
        ProtonAttributeKind::Destroy =>
          FunctionCodegenItem::Destroy(parse_destroy_from_func(func))
        ProtonAttributeKind::Event =>
          raise CommandCodegenError::Attribute(
            kind="event",
            detail="can only annotate a struct",
          )
      }
  }
}

///|
fn parse_command_from_func(
  func : @moonbitlang/parser/syntax.FunDecl,
  attr : ProtonAttribute,
) -> ParsedProtonCommand raise {
  let function_name = func.name.name
  validate_identifier("command function name", function_name)
  let params = match func.decl_params {
    Some(value) => parse_ast_params(function_name, value)
    None => []
  }
  let return_type = match func.return_type {
    Some(ty) =>
      type_expr_text(ty, context="command return type for " + function_name)
    None => "Unit"
  }
  let js_name = match attr.name_override {
    Some(name) => name
    None => lower_camel_from_snake(function_name)
  }
  validate_js_part("command JavaScript name", js_name)
  ParsedProtonCommand::{
    function_name,
    js_name,
    params,
    return_type,
    is_async: func.is_async is Some(_),
    has_context: params.any(fn(param) { param.is_context }),
    has_request_context: params.any(fn(param) { param.is_request_context }),
    error_effect: error_effect_text(
      func.error_type,
      context="command " + function_name,
    ),
  }
}

///|
fn parse_script_from_func(
  func : @moonbitlang/parser/syntax.FunDecl,
) -> ParsedProtonScript raise {
  let function_name = func.name.name
  validate_identifier("script function name", function_name)
  guard func.is_async is None else {
    raise CommandCodegenError::Script(
      function_name~,
      detail="must be synchronous",
    )
  }
  let params = match func.decl_params {
    Some(value) => parse_ast_params(function_name, value)
    None => []
  }
  guard params.length() == 0 else {
    raise CommandCodegenError::Script(
      function_name~,
      detail="must not take parameters",
    )
  }
  let return_type = match func.return_type {
    Some(ty) =>
      type_expr_text(ty, context="script return type for " + function_name)
    None => "Unit"
  }
  guard return_type == "String" else {
    raise CommandCodegenError::Script(
      function_name~,
      detail="must return String",
    )
  }
  ParsedProtonScript::{ function_name, }
}

///|
fn parse_destroy_from_func(
  func : @moonbitlang/parser/syntax.FunDecl,
) -> ParsedProtonDestroy raise {
  let function_name = func.name.name
  validate_identifier("destroy function name", function_name)
  guard func.is_async is None else {
    raise CommandCodegenError::Destroy(
      function_name~,
      detail="must be synchronous",
    )
  }
  let params = match func.decl_params {
    Some(value) => parse_ast_params(function_name, value)
    None => []
  }
  let return_type = match func.return_type {
    Some(ty) =>
      type_expr_text(ty, context="destroy return type for " + function_name)
    None => "Unit"
  }
  guard return_type == "Unit" else {
    raise CommandCodegenError::Destroy(
      function_name~,
      detail="must return Unit",
    )
  }
  guard params.length() <= 1 else {
    raise CommandCodegenError::Destroy(
      function_name~,
      detail="accepts at most one context parameter",
    )
  }
  let has_context = params.any(fn(param) { param.is_context })
  guard params.length() == 0 || has_context else {
    raise CommandCodegenError::Destroy(
      function_name~,
      detail="parameter must be `context : @proton_command.AppCommandExtensionContext`",
    )
  }
  ParsedProtonDestroy::{
    function_name,
    has_context,
    error_effect: error_effect_text(
      func.error_type,
      context="destroy " + function_name,
    ),
  }
}

///|
fn parse_event_from_type_def(
  type_decl : @moonbitlang/parser/syntax.TypeDecl,
  source : String,
) -> ParsedProtonEvent? raise {
  let attrs = collect_proton_attributes(type_decl.attrs, source)
  let event_attr = select_single_proton_attribute(attrs)
  let attr = match event_attr {
    None => return None
    Some(attr) =>
      match attr.kind {
        ProtonAttributeKind::Event => attr
        _ =>
          raise CommandCodegenError::Attribute(
            kind=proton_attribute_kind_label(attr.kind),
            detail="can only annotate a function",
          )
      }
  }
  guard type_decl.components is Record(..) else {
    raise CommandCodegenError::Event(
      type_name=type_decl.tycon,
      detail="can only annotate a struct",
    )
  }
  let type_name = type_decl.tycon
  validate_type_identifier("event payload type", type_name)
  let js_name = match attr.name_override {
    Some(name) => name
    None => lower_camel_from_pascal(type_name)
  }
  validate_js_part("event JavaScript name", js_name)
  Some(ParsedProtonEvent::{
    type_name,
    js_name,
    helper_name: "emit_" + snake_from_camel(type_name),
  })
}

///|
fn collect_proton_attributes(
  attrs : @list.List[@moonbitlang/parser/attribute.Attribute],
  source : String,
) -> Array[ProtonAttribute] raise {
  let parsed : Array[ProtonAttribute] = []
  attrs.each(fn(attr) raise {
    let raw = recover_attr_raw(source, attr)
    if raw.has_prefix("#proton.command") {
      parsed.push(parse_proton_attribute(ProtonAttributeKind::Command, raw))
    } else if raw.has_prefix("#proton.event") {
      parsed.push(parse_proton_attribute(ProtonAttributeKind::Event, raw))
    } else if raw.has_prefix("#proton.script") {
      parsed.push(parse_proton_attribute(ProtonAttributeKind::Script, raw))
    } else if raw.has_prefix("#proton.destroy") {
      parsed.push(parse_proton_attribute(ProtonAttributeKind::Destroy, raw))
    }
  })
  parsed
}

///|
fn parse_proton_attribute(
  kind : ProtonAttributeKind,
  raw : String,
) -> ProtonAttribute raise {
  let label = proton_attribute_kind_label(kind)
  let prefix = "#proton." + label
  if raw == prefix {
    return ProtonAttribute::{ kind, name_override: None }
  }
  guard raw.has_prefix(prefix + "(") && raw.has_suffix(")") else {
    raise CommandCodegenError::Attribute(
      kind=label,
      detail="unsupported attribute syntax: " + raw,
    )
  }
  let inner = raw
    .unsafe_substring(start=prefix.length() + 1, end=raw.length() - 1)
    .trim()
    .to_owned()
  guard inner.has_prefix("name=\"") && inner.has_suffix("\"") else {
    raise CommandCodegenError::Attribute(
      kind=label,
      detail="unsupported attribute arguments: " + raw,
    )
  }
  let name = inner.unsafe_substring(start=6, end=inner.length() - 1)
  guard name != "" else {
    raise CommandCodegenError::Attribute(
      kind=label,
      detail="name must not be empty",
    )
  }
  ProtonAttribute::{ kind, name_override: Some(name) }
}

///|
fn select_single_proton_attribute(
  attrs : Array[ProtonAttribute],
) -> ProtonAttribute? raise {
  let mut selected : ProtonAttribute? = None
  for attr in attrs {
    guard selected is None else {
      raise CommandCodegenError::Attribute(
        kind="attribute",
        detail="only one #proton attribute can be attached to one item",
      )
    }
    selected = Some(attr)
  }
  selected
}

///|
fn proton_attribute_kind_label(kind : ProtonAttributeKind) -> String {
  match kind {
    ProtonAttributeKind::Command => "command"
    ProtonAttributeKind::Event => "event"
    ProtonAttributeKind::Script => "script"
    ProtonAttributeKind::Destroy => "destroy"
  }
}

///|
fn parse_ast_params(
  function_name : String,
  params : @list.List[@moonbitlang/parser/syntax.Parameter],
) -> Array[ParsedProtonParam] raise {
  let out : Array[ParsedProtonParam] = []
  params.each(fn(param) raise {
    match param {
      Positional(binder={ name, .. }, ty=Some(ty)) => {
        let param_type = type_expr_text(
          ty,
          context="command parameter " + function_name + "." + name,
        )
        out.push(ParsedProtonParam::{
          name,
          param_type,
          is_context: name == "context" &&
          param_type == "@proton_command.AppCommandExtensionContext",
          is_request_context: name == "request_context" &&
          param_type == "@proton_command.AppCommandRequestContext",
        })
      }
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
  out
}

///|
fn type_expr_text(
  ty : @moonbitlang/parser/syntax.Type,
  context~ : String,
) -> String raise {
  match ty {
    Name(constr_id~, tys~, ..) =>
      if tys is Empty {
        long_ident_text(constr_id.id)
      } else {
        "\{long_ident_text(constr_id.id)}[\{type_list_text(tys, context~)}]"
      }
    Option(ty=inner, ..) => type_expr_text(inner, context~) + "?"
    Tuple(tys~, ..) => "(\{type_list_text(tys, context~)})"
    _ => raise CommandCodegenError::UnsupportedType(context~)
  }
}

///|
fn long_ident_text(id : @moonbitlang/parser/syntax.LongIdent) -> String {
  match id {
    Ident(name~) => name
    Dot(pkg~, id=target) => "@" + pkg + "." + target
  }
}

///|
fn type_list_text(
  tys : @list.List[@moonbitlang/parser/syntax.Type],
  context~ : String,
) -> String raise {
  let parts : Array[String] = []
  tys.each(fn(ty) raise { parts.push(type_expr_text(ty, context~)) })
  parts.join(", ")
}

///|
fn error_effect_text(
  error_type : @moonbitlang/parser/syntax.ErrorType,
  context~ : String,
) -> String? raise {
  match error_type {
    ErrorType(ty~) =>
      Some("raise " + type_expr_text(ty, context=context + " error type"))
    DefaultErrorType(..) => Some("raise")
    MaybeError(..) => Some("raise?")
    Noraise(..) => Some("noraise")
    NoErrorType => None
  }
}

///|
fn validate_parsed_module(parsed : ParsedProtonModule) -> Unit raise {
  guard parsed.commands.length() > 0 else {
    raise CommandCodegenError::MissingCommand
  }
  for command in parsed.commands {
    if parsed.events.length() == 0 {
      guard !command.has_context else {
        raise CommandCodegenError::Command(
          function_name=command.function_name,
          detail="context parameter requires a generated #proton.event helper",
        )
      }
    }
    let mut context_count = 0
    let mut request_context_count = 0
    for param in command.params {
      if param.is_context {
        context_count = context_count + 1
      }
      if param.is_request_context {
        request_context_count = request_context_count + 1
      }
    }
    guard context_count <= 1 else {
      raise CommandCodegenError::Command(
        function_name=command.function_name,
        detail="only one context parameter is supported",
      )
    }
    guard request_context_count <= 1 else {
      raise CommandCodegenError::Command(
        function_name=command.function_name,
        detail="only one request_context parameter is supported",
      )
    }
    if command.has_request_context {
      guard command.is_async else {
        raise CommandCodegenError::Command(
          function_name=command.function_name,
          detail="request_context parameter requires an async command",
        )
      }
    }
  }
  validate_duplicate_names(
    "command JavaScript name",
    parsed.commands.map(fn(command) { command.js_name }),
    parsed.package_commands.map(fn(command) { command.js_name }),
  )
  validate_duplicate_names(
    "event JavaScript name",
    parsed.events.map(fn(event) { event.js_name }),
    parsed.package_events.map(fn(event) { event.js_name }),
  )
}

///|
fn validate_duplicate_names(
  label : String,
  local_names : Array[String],
  package_names : Array[String],
) -> Unit raise {
  let names : Map[String, Bool] = Map([])
  for name in package_names {
    names[name] = true
  }
  for name in local_names {
    guard names.get(name) is None else {
      raise CommandCodegenError::Duplicate(kind=label, name~)
    }
    names[name] = true
  }
}

///|
fn recover_attr_raw(
  source : String,
  attr : @moonbitlang/parser/attribute.Attribute,
) -> String {
  let raw = attr.raw
  if raw.contains("(") {
    return raw
  }
  let loc = attr.loc
  let start_str = loc.start.to_string()
  let parse_pos = fn(s : String) -> (Int, Int) {
    let mut text = s
    if text.has_prefix("\"") && text.length() >= 2 {
      text = text[1:text.length()].to_owned()
    }
    if text.has_suffix("\"") && text.length() >= 1 {
      text = text[0:text.length() - 1].to_owned()
    }
    let parts = text.split(":").collect()
    if parts.length() >= 2 {
      (
        @string.parse_int(parts[parts.length() - 2]) catch {
          _ => -1
        },
        @string.parse_int(parts[parts.length() - 1]) catch {
          _ => -1
        },
      )
    } else {
      (-1, -1)
    }
  }
  let (line, col) = parse_pos(start_str)
  let lines = source.split("\n").collect()
  let idx = line - 1
  guard idx >= 0 && idx < lines.length() else { return raw }
  let full = lines[idx].to_owned()
  let start = col - 1
  guard start >= 0 && start < full.length() else { return raw }
  full[start:].trim().to_owned()
}

///|
fn path_dirname(path : String) -> String {
  let mut cut : Int? = None
  for i, ch in path {
    if ch == '/' || ch == '\\' {
      cut = Some(i)
    }
  }
  match cut {
    Some(0) => path.unsafe_substring(start=0, end=1)
    Some(i) => path.unsafe_substring(start=0, end=i)
    None => "."
  }
}

///|
fn path_join(dir : String, name : String) -> String {
  if dir == "." || dir == "" {
    name
  } else if dir.has_suffix("/") || dir.has_suffix("\\") {
    dir + name
  } else {
    dir + "/" + name
  }
}

///|
fn path_basename(path : String) -> String {
  let mut cut : Int? = None
  for i, ch in path {
    if ch == '/' || ch == '\\' {
      cut = Some(i)
    }
  }
  match cut {
    Some(i) => path.unsafe_substring(start=i + 1, end=path.length())
    None => path
  }
}

///|
fn normalize_path(path : String) -> String {
  path.replace(old="\\", new="/")
}
