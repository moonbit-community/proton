///|
/// Generates Lepus command extension MoonBit source from one source string.
///
/// This entry point parses only `source`; it is intended for unit tests and
/// callers that already have the full package context in memory.
pub fn generate_app_commands_from_source(
  source : String,
  extension_id : String,
  js_namespace : String,
) -> Result[LepusCommandCodegenOutput, String] {
  validate_non_empty("extension id", extension_id).bind(fn(_) {
    validate_js_part("extension namespace", js_namespace).bind(fn(_) {
      let (ast, reports) = @parser.parse_string(source)
      guard reports.is_empty() else {
        return Err("failed to parse MoonBit source for #lepus codegen")
      }
      parse_lepus_ast(ast, source).bind(fn(base) {
        let parsed = ParsedLepusModule::{
          commands: base.commands,
          events: base.events,
          scripts: base.scripts,
          destroy: base.destroy,
          package_commands: [],
          package_events: [],
        }
        validate_parsed_module(parsed).map(fn(_) {
          render_lepus_command_codegen(parsed, extension_id, js_namespace)
        })
      })
    })
  })
}

///|
/// Generates Lepus command extension MoonBit source from one input file.
///
/// The input file's package directory is scanned for ordinary `.mbt` files so
/// duplicate command and event names can be checked against sibling sources.
pub fn generate_app_commands_from_file(
  input_file : String,
  extension_id : String,
  js_namespace : String,
) -> Result[LepusCommandCodegenOutput, String] {
  validate_extension_id(extension_id).bind(fn(_) {
    validate_js_part("extension namespace", js_namespace).bind(fn(_) {
      let parsed_result = collect_package_lepus_module(input_file) catch {
        err => return Err(@debug.render(@debug.to_repr(err)))
      }
      let parsed = match parsed_result {
        Ok(parsed) => parsed
        Err(error) => return Err(error)
      }
      validate_parsed_module(parsed).map(fn(_) {
        render_lepus_command_codegen(parsed, extension_id, js_namespace)
      })
    })
  })
}

///|
/// Generates Lepus command extension MoonBit source using extension metadata.
///
/// The codegen input's package directory must contain `extension.json` with an
/// `id` field. `namespace` is optional and is inferred from the id when absent.
pub fn generate_app_commands_from_file_with_metadata(
  input_file : String,
) -> Result[LepusCommandCodegenOutput, String] {
  let config_result = read_package_extension_config(input_file) catch {
    err => return Err(@debug.render(@debug.to_repr(err)))
  }
  let (extension_id, js_namespace) = match config_result {
    Ok(config) => config
    Err(error) => return Err(error)
  }
  generate_app_commands_from_file(input_file, extension_id, js_namespace)
}

///|
fn read_package_extension_config(
  input_file : String,
) -> Result[(String, String), String] raise @mbfs.IOError {
  let extension_path = path_join(path_dirname(input_file), "extension.json")
  let has_metadata = @mbfs.is_file(extension_path) catch { _ => false }
  guard has_metadata else {
    return Err("missing extension.json next to input file")
  }
  let (id, js_namespace) = match read_extension_codegen_config(extension_path) {
    Ok(config) => config
    Err(error) => return Err(error)
  }
  match validate_extension_id(id) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match validate_js_part("extension namespace", js_namespace) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok((id, js_namespace))
}

///|
fn read_extension_codegen_config(
  path : String,
) -> Result[(String, String), String] raise @mbfs.IOError {
  let text = @mbfs.read_file_to_string(path)
  try @json.parse(text) catch {
    error => Err("failed to parse extension.json: " + error.to_string())
  } noraise {
    json => decode_extension_codegen_config(json)
  }
}

///|
fn decode_extension_codegen_config(
  json : Json,
) -> Result[(String, String), String] {
  match json {
    Object(object) => {
      let id = match object.get("id") {
        Some(String(value)) => value
        Some(_) => return Err("extension.json field `id` must be a string")
        None => return Err("extension.json must contain string field `id`")
      }
      let js_namespace = match object.get("namespace") {
        Some(String(value)) => value
        Some(_) =>
          return Err("extension.json field `namespace` must be a string")
        None => lower_camel_from_id(id)
      }
      Ok((id, js_namespace))
    }
    _ => Err("extension.json must contain a JSON object")
  }
}

///|
fn collect_package_lepus_module(
  input_file : String,
) -> Result[ParsedLepusModule, String] raise @mbfs.IOError {
  let input_path = normalize_path(input_file)
  let dir = path_dirname(input_file)
  let target = ParsedLepusModule::{
    commands: [],
    events: [],
    scripts: [],
    destroy: None,
    package_commands: [],
    package_events: [],
  }
  let context = ParsedLepusModule::{
    commands: [],
    events: [],
    scripts: [],
    destroy: None,
    package_commands: [],
    package_events: [],
  }
  for entry in @mbfs.read_dir(dir) {
    guard is_codegen_source_file(entry) else { continue }
    let path = path_join(dir, entry)
    guard @mbfs.is_file(path) else { continue }
    let is_target = normalize_path(path) == input_path ||
      entry == path_basename(input_file)
    let source = @mbfs.read_file_to_string(path)
    let (ast, reports) = @parser.parse_file(path)
    if !reports.is_empty() {
      guard !is_target else {
        return Err(
          "failed to parse MoonBit source for #lepus codegen: " + input_file,
        )
      }
      continue
    }
    let parsed = match parse_lepus_ast(ast, source) {
      Ok(parsed) => parsed
      Err(error) => return Err(error)
    }
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
  Ok(ParsedLepusModule::{
    commands: target.commands,
    events: target.events,
    scripts: target.scripts,
    destroy: target.destroy,
    package_commands: context.commands,
    package_events: context.events,
  })
}

///|
fn is_codegen_source_file(name : String) -> Bool {
  name.has_suffix(".mbt") &&
  !name.has_suffix(".g.mbt") &&
  !name.has_suffix("_test.mbt") &&
  !name.has_suffix("_wbtest.mbt")
}

///|
fn parse_lepus_ast(
  ast : @list.List[@moonbitlang/parser/syntax.Impl],
  source : String,
) -> Result[ParsedLepusModule, String] {
  let commands : Array[ParsedLepusCommand] = []
  let events : Array[ParsedLepusEvent] = []
  let scripts : Array[ParsedLepusScript] = []
  let mut destroy : ParsedLepusDestroy? = None
  let mut first_error : String? = None
  ast.each(fn(item) {
    if first_error is Some(_) {
      return
    }
    match item {
      TopFuncDef(fun_decl~, ..) =>
        match parse_func_codegen_item(fun_decl, source) {
          Ok(FunctionCodegenItem::None) => ()
          Ok(Command(command)) => commands.push(command)
          Ok(Script(script)) => scripts.push(script)
          Ok(Destroy(next_destroy)) =>
            match destroy {
              Some(_) =>
                first_error = Some(
                  "only one #lepus.destroy attribute is supported",
                )
              None => destroy = Some(next_destroy)
            }
          Err(error) => first_error = Some(error)
        }
      TopTypeDef(type_decl) =>
        match parse_event_from_type_def(type_decl, source) {
          Ok(Some(event)) => events.push(event)
          Ok(None) => ()
          Err(error) => first_error = Some(error)
        }
      _ => ()
    }
  })
  if first_error is Some(error) {
    return Err(error)
  }
  Ok(ParsedLepusModule::{
    commands,
    events,
    scripts,
    destroy,
    package_commands: [],
    package_events: [],
  })
}

///|
priv enum FunctionCodegenItem {
  None
  Command(ParsedLepusCommand)
  Script(ParsedLepusScript)
  Destroy(ParsedLepusDestroy)
}

///|
fn parse_func_codegen_item(
  func : @moonbitlang/parser/syntax.FunDecl,
  source : String,
) -> Result[FunctionCodegenItem, String] {
  let attrs = match collect_lepus_attributes(func.attrs, source) {
    Ok(attrs) => attrs
    Err(error) => return Err(error)
  }
  match select_single_lepus_attribute(attrs) {
    Err(error) => Err(error)
    Ok(None) => Ok(FunctionCodegenItem::None)
    Ok(Some(attr)) =>
      match attr.kind {
        LepusAttributeKind::Command =>
          parse_command_from_func(func, attr).map(fn(command) {
            FunctionCodegenItem::Command(command)
          })
        LepusAttributeKind::Script =>
          parse_script_from_func(func).map(fn(script) {
            FunctionCodegenItem::Script(script)
          })
        LepusAttributeKind::Destroy =>
          parse_destroy_from_func(func).map(fn(destroy) {
            FunctionCodegenItem::Destroy(destroy)
          })
        LepusAttributeKind::Event =>
          Err("#lepus.event can only annotate a struct")
      }
  }
}

///|
fn parse_command_from_func(
  func : @moonbitlang/parser/syntax.FunDecl,
  attr : LepusAttribute,
) -> Result[ParsedLepusCommand, String] {
  let function_name = func.name.name
  match validate_identifier("command function name", function_name) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let params = match func.decl_params {
    Some(value) =>
      match parse_ast_params(function_name, value) {
        Ok(params) => params
        Err(error) => return Err(error)
      }
    None => []
  }
  let return_type = match func.return_type {
    Some(ty) =>
      match type_expr_text(ty) {
        Ok(text) => text
        Err(_) =>
          return Err(
            "unsupported command return type in #lepus.command: " +
            function_name,
          )
      }
    None => "Unit"
  }
  let js_name = match attr.name_override {
    Some(name) => name
    None => lower_camel_from_snake(function_name)
  }
  match validate_js_part("command JavaScript name", js_name) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok(ParsedLepusCommand::{
    function_name,
    js_name,
    params,
    return_type,
    is_async: func.is_async is Some(_),
    has_context: params.any(fn(param) { param.is_context }),
    returns_result: result_ok_type(return_type) is Some(_),
  })
}

///|
fn parse_script_from_func(
  func : @moonbitlang/parser/syntax.FunDecl,
) -> Result[ParsedLepusScript, String] {
  let function_name = func.name.name
  match validate_identifier("script function name", function_name) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  guard func.is_async is None else {
    return Err("#lepus.script function must be synchronous: " + function_name)
  }
  let params = match func.decl_params {
    Some(value) =>
      match parse_ast_params(function_name, value) {
        Ok(params) => params
        Err(error) => return Err(error)
      }
    None => []
  }
  guard params.length() == 0 else {
    return Err(
      "#lepus.script function must not take parameters: " + function_name,
    )
  }
  let return_type = match func.return_type {
    Some(ty) =>
      match type_expr_text(ty) {
        Ok(text) => text
        Err(_) =>
          return Err("unsupported #lepus.script return type: " + function_name)
      }
    None => "Unit"
  }
  guard return_type == "String" else {
    return Err("#lepus.script function must return String: " + function_name)
  }
  Ok(ParsedLepusScript::{ function_name, })
}

///|
fn parse_destroy_from_func(
  func : @moonbitlang/parser/syntax.FunDecl,
) -> Result[ParsedLepusDestroy, String] {
  let function_name = func.name.name
  match validate_identifier("destroy function name", function_name) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  guard func.is_async is None else {
    return Err("#lepus.destroy function must be synchronous: " + function_name)
  }
  let params = match func.decl_params {
    Some(value) =>
      match parse_ast_params(function_name, value) {
        Ok(params) => params
        Err(error) => return Err(error)
      }
    None => []
  }
  let return_type = match func.return_type {
    Some(ty) =>
      match type_expr_text(ty) {
        Ok(text) => text
        Err(_) =>
          return Err("unsupported #lepus.destroy return type: " + function_name)
      }
    None => "Unit"
  }
  guard return_type == "Unit" else {
    return Err("#lepus.destroy function must return Unit: " + function_name)
  }
  guard params.length() <= 1 else {
    return Err(
      "#lepus.destroy function accepts at most one context parameter: " +
      function_name,
    )
  }
  let has_context = params.any(fn(param) { param.is_context })
  guard params.length() == 0 || has_context else {
    return Err(
      "#lepus.destroy parameter must be `context : @lepus.AppCommandExtensionContext`: " +
      function_name,
    )
  }
  Ok(ParsedLepusDestroy::{ function_name, has_context })
}

///|
fn parse_event_from_type_def(
  type_decl : @moonbitlang/parser/syntax.TypeDecl,
  source : String,
) -> Result[ParsedLepusEvent?, String] {
  let attrs = match collect_lepus_attributes(type_decl.attrs, source) {
    Ok(attrs) => attrs
    Err(error) => return Err(error)
  }
  let event_attr = match select_single_lepus_attribute(attrs) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let attr = match event_attr {
    None => return Ok(None)
    Some(attr) =>
      match attr.kind {
        LepusAttributeKind::Event => attr
        _ =>
          return Err(
            "#lepus." +
            lepus_attribute_kind_label(attr.kind) +
            " can only annotate a function",
          )
      }
  }
  guard type_decl.components is Record(..) else {
    return Err("#lepus.event can only annotate a struct")
  }
  let type_name = type_decl.tycon
  match validate_type_identifier("event payload type", type_name) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let js_name = match attr.name_override {
    Some(name) => name
    None => lower_camel_from_pascal(type_name)
  }
  match validate_js_part("event JavaScript name", js_name) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok(
    Some(ParsedLepusEvent::{
      type_name,
      js_name,
      helper_name: "emit_" + snake_from_camel(type_name),
    }),
  )
}

///|
fn collect_lepus_attributes(
  attrs : @list.List[@moonbitlang/parser/attribute.Attribute],
  source : String,
) -> Result[Array[LepusAttribute], String] {
  let parsed : Array[LepusAttribute] = []
  let mut first_error : String? = None
  attrs.each(fn(attr) {
    if first_error is Some(_) {
      return
    }
    let raw = recover_attr_raw(source, attr)
    if raw.has_prefix("#lepus.command") {
      match parse_lepus_attribute(LepusAttributeKind::Command, raw) {
        Ok(attr) => parsed.push(attr)
        Err(error) => first_error = Some(error)
      }
    } else if raw.has_prefix("#lepus.event") {
      match parse_lepus_attribute(LepusAttributeKind::Event, raw) {
        Ok(attr) => parsed.push(attr)
        Err(error) => first_error = Some(error)
      }
    } else if raw.has_prefix("#lepus.script") {
      match parse_lepus_attribute(LepusAttributeKind::Script, raw) {
        Ok(attr) => parsed.push(attr)
        Err(error) => first_error = Some(error)
      }
    } else if raw.has_prefix("#lepus.destroy") {
      match parse_lepus_attribute(LepusAttributeKind::Destroy, raw) {
        Ok(attr) => parsed.push(attr)
        Err(error) => first_error = Some(error)
      }
    }
  })
  match first_error {
    Some(error) => Err(error)
    None => Ok(parsed)
  }
}

///|
fn parse_lepus_attribute(
  kind : LepusAttributeKind,
  raw : String,
) -> Result[LepusAttribute, String] {
  let label = lepus_attribute_kind_label(kind)
  let prefix = "#lepus." + label
  if raw == prefix {
    return Ok(LepusAttribute::{ kind, name_override: None })
  }
  guard raw.has_prefix(prefix + "(") && raw.has_suffix(")") else {
    return Err("unsupported #lepus." + label + " attribute syntax: " + raw)
  }
  let inner = raw
    .unsafe_substring(start=prefix.length() + 1, end=raw.length() - 1)
    .trim()
    .to_owned()
  guard inner.has_prefix("name=\"") && inner.has_suffix("\"") else {
    return Err("unsupported #lepus." + label + " attribute arguments: " + raw)
  }
  let name = inner.unsafe_substring(start=6, end=inner.length() - 1)
  guard name != "" else {
    return Err("#lepus." + label + " name must not be empty")
  }
  Ok(LepusAttribute::{ kind, name_override: Some(name) })
}

///|
fn select_single_lepus_attribute(
  attrs : Array[LepusAttribute],
) -> Result[LepusAttribute?, String] {
  let mut selected : LepusAttribute? = None
  for attr in attrs {
    guard selected is None else {
      return Err("only one #lepus attribute can be attached to one item")
    }
    selected = Some(attr)
  }
  Ok(selected)
}

///|
fn lepus_attribute_kind_label(kind : LepusAttributeKind) -> String {
  match kind {
    LepusAttributeKind::Command => "command"
    LepusAttributeKind::Event => "event"
    LepusAttributeKind::Script => "script"
    LepusAttributeKind::Destroy => "destroy"
  }
}

///|
fn parse_ast_params(
  function_name : String,
  params : @list.List[@moonbitlang/parser/syntax.Parameter],
) -> Result[Array[ParsedLepusParam], String] {
  let out : Array[ParsedLepusParam] = []
  let mut first_error : String? = None
  params.each(fn(param) {
    if first_error is Some(_) {
      return
    }
    match param {
      Positional(binder={ name, .. }, ty=Some(ty)) =>
        match type_expr_text(ty) {
          Err(_) =>
            first_error = Some(
              "unsupported command parameter type in #lepus.command: " +
              function_name +
              "." +
              name,
            )
          Ok(param_type) =>
            out.push(ParsedLepusParam::{
              name,
              param_type,
              is_context: name == "context" &&
              param_type == "@lepus.AppCommandExtensionContext",
            })
        }
      DiscardPositional(..) =>
        first_error = Some(
          "discard parameters are not supported by #lepus.command: " +
          function_name,
        )
      Labelled(..) =>
        first_error = Some(
          "labeled and optional-parameter syntax is not supported by #lepus.command: " +
          function_name,
        )
      _ =>
        first_error = Some(
          "command parameter must use `name : Type`: " + function_name,
        )
    }
  })
  if first_error is Some(error) {
    return Err(error)
  }
  Ok(out)
}

///|
fn type_expr_text(
  ty : @moonbitlang/parser/syntax.Type,
) -> Result[String, String] {
  match ty {
    Name(constr_id~, tys~, ..) =>
      if tys is Empty {
        Ok(long_ident_text(constr_id.id))
      } else {
        match type_list_text(tys) {
          Ok(text) => Ok("\{long_ident_text(constr_id.id)}[\{text}]")
          Err(error) => Err(error)
        }
      }
    Option(ty=inner, ..) =>
      match type_expr_text(inner) {
        Ok(text) => Ok(text + "?")
        Err(error) => Err(error)
      }
    Tuple(tys~, ..) =>
      match type_list_text(tys) {
        Ok(text) => Ok("(\{text})")
        Err(error) => Err(error)
      }
    _ => Err("unsupported type")
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
) -> Result[String, String] {
  let parts : Array[String] = []
  let mut first_error : String? = None
  tys.each(fn(ty) {
    if first_error is Some(_) {
      return
    }
    match type_expr_text(ty) {
      Ok(text) => parts.push(text)
      Err(error) => first_error = Some(error)
    }
  })
  match first_error {
    Some(error) => Err(error)
    None => Ok(parts.join(", "))
  }
}

///|
fn result_ok_type(type_name : String) -> String? {
  let trimmed = type_name.trim().to_owned()
  guard trimmed.has_prefix("Result[") && trimmed.has_suffix("]") else {
    return None
  }
  let inner = trimmed.unsafe_substring(start=7, end=trimmed.length() - 1)
  let parts = split_top_level_commas(inner)
  guard parts.length() == 2 else { return None }
  guard parts[1].trim().to_owned() == "String" else { return None }
  Some(parts[0].trim().to_owned())
}

///|
fn validate_parsed_module(parsed : ParsedLepusModule) -> Result[Unit, String] {
  guard parsed.commands.length() > 0 else {
    return Err("#lepus.command codegen requires at least one command")
  }
  for command in parsed.commands {
    if parsed.events.length() == 0 {
      guard !command.has_context else {
        return Err(
          "context parameter is only supported when #lepus.event helpers are generated: " +
          command.function_name,
        )
      }
    }
    let mut context_count = 0
    for param in command.params {
      if param.is_context {
        context_count = context_count + 1
      }
    }
    guard context_count <= 1 else {
      return Err(
        "only one context parameter is supported by #lepus.command: " +
        command.function_name,
      )
    }
  }
  match
    validate_duplicate_names(
      "command JavaScript name",
      parsed.commands.map(fn(command) { command.js_name }),
      parsed.package_commands.map(fn(command) { command.js_name }),
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match
    validate_duplicate_names(
      "event JavaScript name",
      parsed.events.map(fn(event) { event.js_name }),
      parsed.package_events.map(fn(event) { event.js_name }),
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok(())
}

///|
fn validate_duplicate_names(
  label : String,
  local_names : Array[String],
  package_names : Array[String],
) -> Result[Unit, String] {
  let names : Map[String, Bool] = {}
  for name in package_names {
    names[name] = true
  }
  for name in local_names {
    guard names.get(name) is None else {
      return Err("duplicate " + label + ": " + name)
    }
    names[name] = true
  }
  Ok(())
}

///|
fn split_top_level_commas(text : String) -> Array[String] {
  let parts : Array[String] = []
  let mut start = 0
  let mut square = 0
  let mut paren = 0
  for i, ch in text {
    if ch == '[' {
      square = square + 1
    } else if ch == ']' {
      square = square - 1
    } else if ch == '(' {
      paren = paren + 1
    } else if ch == ')' {
      paren = paren - 1
    } else if ch == ',' && square == 0 && paren == 0 {
      parts.push(text.unsafe_substring(start~, end=i))
      start = i + 1
    }
  }
  parts.push(text.unsafe_substring(start~, end=text.length()))
  parts
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
