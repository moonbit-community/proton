///|
/// Generates Proton command extension MoonBit source from one source string.
///
/// This entry point parses only `source`; it is intended for unit tests and
/// callers that already have the full package context in memory.
pub fn generate_app_commands_from_source(
  source : String,
  extension_id : String,
  js_namespace : String,
) -> Result[ProtonCommandCodegenOutput, String] {
  validate_non_empty("extension id", extension_id).bind(fn(_) {
    validate_js_part("extension namespace", js_namespace).bind(fn(_) {
      let (ast, reports) = @parser.parse_string(source)
      guard reports.is_empty() else {
        return Err("failed to parse MoonBit source for #proton codegen")
      }
      parse_proton_ast(ast, source).bind(fn(base) {
        let parsed = ParsedProtonModule::{
          commands: base.commands,
          events: base.events,
          scripts: base.scripts,
          destroy: base.destroy,
          package_commands: [],
          package_events: [],
        }
        validate_parsed_module(parsed).map(fn(_) {
          render_proton_command_codegen(parsed, extension_id, js_namespace)
        })
      })
    })
  })
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
) -> Result[ProtonCommandCodegenOutput, String] {
  validate_extension_id(extension_id).bind(fn(_) {
    validate_js_part("extension namespace", js_namespace).bind(fn(_) {
      let parsed_result = collect_package_proton_module(input_file) catch {
        err => return Err(@debug.render(@debug.to_repr(err)))
      }
      let parsed = match parsed_result {
        Ok(parsed) => parsed
        Err(error) => return Err(error)
      }
      validate_parsed_module(parsed).map(fn(_) {
        render_proton_command_codegen(parsed, extension_id, js_namespace)
      })
    })
  })
}

///|
/// Generates Proton command extension MoonBit source using extension metadata.
///
/// The codegen input's package directory must contain `moon.ext` with string
/// `id` and `namespace` fields.
pub fn generate_app_commands_from_file_with_metadata(
  input_file : String,
) -> Result[ProtonCommandCodegenOutput, String] {
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
  let package_dir = path_dirname(input_file)
  let moon_ext_path = path_join(package_dir, "moon.ext")
  let has_moon_ext = @mbfs.is_file(moon_ext_path) catch { _ => false }
  guard has_moon_ext else { return Err("missing moon.ext next to input file") }
  let (id, js_namespace) = match
    read_moon_ext_codegen_config_file(moon_ext_path) {
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
fn read_moon_ext_codegen_config_file(
  path : String,
) -> Result[(String, String), String] raise @mbfs.IOError {
  let text = @mbfs.read_file_to_string(path)
  read_moon_ext_codegen_config(path, text)
}

///|
/// Validates a `moon.ext` file and returns its extension id and JavaScript namespace.
pub fn read_moon_ext_identity(
  path : String,
) -> Result[(String, String), String] {
  try read_moon_ext_codegen_config_file(path) catch {
    err => Err(@debug.render(@debug.to_repr(err)))
  } noraise {
    result => result
  }
}

///|
fn read_moon_ext_codegen_config(
  path : String,
  text : String,
) -> Result[(String, String), String] {
  let (ast, reports) = @proton_config.parse_moon_ext(name=path, text)
  if reports.length() > 0 {
    return Err(render_moon_ext_config_reports(reports))
  }
  match ast {
    Obj(fields, _) => read_moon_ext_codegen_fields(fields)
    _ => Err("expected field list for moon.ext")
  }
}

///|
fn read_moon_ext_codegen_fields(
  fields : Array[@proton_config.ConfigField],
) -> Result[(String, String), String] {
  validate_moon_ext_codegen_fields(fields).bind(fn(_) {
    moon_ext_codegen_required_string(fields, "id").bind(fn(id) {
      moon_ext_codegen_required_string(fields, "namespace").map(fn(
        js_namespace,
      ) {
        (id, js_namespace)
      })
    })
  })
}

///|
fn validate_moon_ext_codegen_fields(
  fields : Array[@proton_config.ConfigField],
) -> Result[Unit, String] {
  let seen : Map[String, Bool] = Map([])
  for field in fields {
    guard !seen.contains(field.key) else {
      return Err("duplicate moon.ext field: " + field.key)
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
          _ => return Err("moon.ext field `" + field.key + "` must be a string")
        }
      "package" =>
        match field.value {
          Str(value, _) =>
            match validate_npm_package_name(value) {
              Ok(_) => ()
              Err(error) => return Err(error)
            }
          _ => return Err("moon.ext field `package` must be a string")
        }
      "keywords" | "platforms" | "dependencies" =>
        match field.value {
          Arr(_, _) => ()
          _ => return Err("moon.ext field `" + field.key + "` must be an array")
        }
      other => return Err("unknown moon.ext field: " + other)
    }
  }
  Ok(())
}

///|
fn moon_ext_codegen_required_string(
  fields : Array[@proton_config.ConfigField],
  key : String,
) -> Result[String, String] {
  for field in fields {
    if field.key == key {
      match field.value {
        Str(value, _) => return Ok(value)
        _ => return Err("moon.ext field `" + key + "` must be a string")
      }
    }
  }
  Err("moon.ext must contain string field `" + key + "`")
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
) -> Result[ParsedProtonModule, String] raise @mbfs.IOError {
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
          "failed to parse MoonBit source for #proton codegen: " + input_file,
        )
      }
      continue
    }
    let parsed = match parse_proton_ast(ast, source) {
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
  Ok(ParsedProtonModule::{
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
fn parse_proton_ast(
  ast : @list.List[@moonbitlang/parser/syntax.Impl],
  source : String,
) -> Result[ParsedProtonModule, String] {
  let commands : Array[ParsedProtonCommand] = []
  let events : Array[ParsedProtonEvent] = []
  let scripts : Array[ParsedProtonScript] = []
  let mut destroy : ParsedProtonDestroy? = None
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
                  "only one #proton.destroy attribute is supported",
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
  Ok(ParsedProtonModule::{
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
  Command(ParsedProtonCommand)
  Script(ParsedProtonScript)
  Destroy(ParsedProtonDestroy)
}

///|
fn parse_func_codegen_item(
  func : @moonbitlang/parser/syntax.FunDecl,
  source : String,
) -> Result[FunctionCodegenItem, String] {
  let attrs = match collect_proton_attributes(func.attrs, source) {
    Ok(attrs) => attrs
    Err(error) => return Err(error)
  }
  match select_single_proton_attribute(attrs) {
    Err(error) => Err(error)
    Ok(None) => Ok(FunctionCodegenItem::None)
    Ok(Some(attr)) =>
      match attr.kind {
        ProtonAttributeKind::Command =>
          parse_command_from_func(func, attr).map(fn(command) {
            FunctionCodegenItem::Command(command)
          })
        ProtonAttributeKind::Script =>
          parse_script_from_func(func).map(fn(script) {
            FunctionCodegenItem::Script(script)
          })
        ProtonAttributeKind::Destroy =>
          parse_destroy_from_func(func).map(fn(destroy) {
            FunctionCodegenItem::Destroy(destroy)
          })
        ProtonAttributeKind::Event =>
          Err("#proton.event can only annotate a struct")
      }
  }
}

///|
fn parse_command_from_func(
  func : @moonbitlang/parser/syntax.FunDecl,
  attr : ProtonAttribute,
) -> Result[ParsedProtonCommand, String] {
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
            "unsupported command return type in #proton.command: " +
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
  Ok(ParsedProtonCommand::{
    function_name,
    js_name,
    params,
    return_type,
    is_async: func.is_async is Some(_),
    has_context: params.any(fn(param) { param.is_context }),
    has_request_context: params.any(fn(param) { param.is_request_context }),
    returns_result: result_ok_type(return_type) is Some(_),
  })
}

///|
fn parse_script_from_func(
  func : @moonbitlang/parser/syntax.FunDecl,
) -> Result[ParsedProtonScript, String] {
  let function_name = func.name.name
  match validate_identifier("script function name", function_name) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  guard func.is_async is None else {
    return Err("#proton.script function must be synchronous: " + function_name)
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
      "#proton.script function must not take parameters: " + function_name,
    )
  }
  let return_type = match func.return_type {
    Some(ty) =>
      match type_expr_text(ty) {
        Ok(text) => text
        Err(_) =>
          return Err("unsupported #proton.script return type: " + function_name)
      }
    None => "Unit"
  }
  guard return_type == "String" else {
    return Err("#proton.script function must return String: " + function_name)
  }
  Ok(ParsedProtonScript::{ function_name, })
}

///|
fn parse_destroy_from_func(
  func : @moonbitlang/parser/syntax.FunDecl,
) -> Result[ParsedProtonDestroy, String] {
  let function_name = func.name.name
  match validate_identifier("destroy function name", function_name) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  guard func.is_async is None else {
    return Err("#proton.destroy function must be synchronous: " + function_name)
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
            "unsupported #proton.destroy return type: " + function_name,
          )
      }
    None => "Unit"
  }
  guard return_type == "Unit" else {
    return Err("#proton.destroy function must return Unit: " + function_name)
  }
  guard params.length() <= 1 else {
    return Err(
      "#proton.destroy function accepts at most one context parameter: " +
      function_name,
    )
  }
  let has_context = params.any(fn(param) { param.is_context })
  guard params.length() == 0 || has_context else {
    return Err(
      "#proton.destroy parameter must be `context : @proton_command.AppCommandExtensionContext`: " +
      function_name,
    )
  }
  Ok(ParsedProtonDestroy::{ function_name, has_context })
}

///|
fn parse_event_from_type_def(
  type_decl : @moonbitlang/parser/syntax.TypeDecl,
  source : String,
) -> Result[ParsedProtonEvent?, String] {
  let attrs = match collect_proton_attributes(type_decl.attrs, source) {
    Ok(attrs) => attrs
    Err(error) => return Err(error)
  }
  let event_attr = match select_single_proton_attribute(attrs) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let attr = match event_attr {
    None => return Ok(None)
    Some(attr) =>
      match attr.kind {
        ProtonAttributeKind::Event => attr
        _ =>
          return Err(
            "#proton." +
            proton_attribute_kind_label(attr.kind) +
            " can only annotate a function",
          )
      }
  }
  guard type_decl.components is Record(..) else {
    return Err("#proton.event can only annotate a struct")
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
    Some(ParsedProtonEvent::{
      type_name,
      js_name,
      helper_name: "emit_" + snake_from_camel(type_name),
    }),
  )
}

///|
fn collect_proton_attributes(
  attrs : @list.List[@moonbitlang/parser/attribute.Attribute],
  source : String,
) -> Result[Array[ProtonAttribute], String] {
  let parsed : Array[ProtonAttribute] = []
  let mut first_error : String? = None
  attrs.each(fn(attr) {
    if first_error is Some(_) {
      return
    }
    let raw = recover_attr_raw(source, attr)
    if raw.has_prefix("#proton.command") {
      match parse_proton_attribute(ProtonAttributeKind::Command, raw) {
        Ok(attr) => parsed.push(attr)
        Err(error) => first_error = Some(error)
      }
    } else if raw.has_prefix("#proton.event") {
      match parse_proton_attribute(ProtonAttributeKind::Event, raw) {
        Ok(attr) => parsed.push(attr)
        Err(error) => first_error = Some(error)
      }
    } else if raw.has_prefix("#proton.script") {
      match parse_proton_attribute(ProtonAttributeKind::Script, raw) {
        Ok(attr) => parsed.push(attr)
        Err(error) => first_error = Some(error)
      }
    } else if raw.has_prefix("#proton.destroy") {
      match parse_proton_attribute(ProtonAttributeKind::Destroy, raw) {
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
fn parse_proton_attribute(
  kind : ProtonAttributeKind,
  raw : String,
) -> Result[ProtonAttribute, String] {
  let label = proton_attribute_kind_label(kind)
  let prefix = "#proton." + label
  if raw == prefix {
    return Ok(ProtonAttribute::{ kind, name_override: None })
  }
  guard raw.has_prefix(prefix + "(") && raw.has_suffix(")") else {
    return Err("unsupported #proton." + label + " attribute syntax: " + raw)
  }
  let inner = raw
    .unsafe_substring(start=prefix.length() + 1, end=raw.length() - 1)
    .trim()
    .to_owned()
  guard inner.has_prefix("name=\"") && inner.has_suffix("\"") else {
    return Err("unsupported #proton." + label + " attribute arguments: " + raw)
  }
  let name = inner.unsafe_substring(start=6, end=inner.length() - 1)
  guard name != "" else {
    return Err("#proton." + label + " name must not be empty")
  }
  Ok(ProtonAttribute::{ kind, name_override: Some(name) })
}

///|
fn select_single_proton_attribute(
  attrs : Array[ProtonAttribute],
) -> Result[ProtonAttribute?, String] {
  let mut selected : ProtonAttribute? = None
  for attr in attrs {
    guard selected is None else {
      return Err("only one #proton attribute can be attached to one item")
    }
    selected = Some(attr)
  }
  Ok(selected)
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
) -> Result[Array[ParsedProtonParam], String] {
  let out : Array[ParsedProtonParam] = []
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
              "unsupported command parameter type in #proton.command: " +
              function_name +
              "." +
              name,
            )
          Ok(param_type) =>
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
        first_error = Some(
          "discard parameters are not supported by #proton.command: " +
          function_name,
        )
      Labelled(..) =>
        first_error = Some(
          "labeled and optional-parameter syntax is not supported by #proton.command: " +
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
fn validate_parsed_module(parsed : ParsedProtonModule) -> Result[Unit, String] {
  guard parsed.commands.length() > 0 else {
    return Err("#proton.command codegen requires at least one command")
  }
  for command in parsed.commands {
    if parsed.events.length() == 0 {
      guard !command.has_context else {
        return Err(
          "context parameter is only supported when #proton.event helpers are generated: " +
          command.function_name,
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
      return Err(
        "only one context parameter is supported by #proton.command: " +
        command.function_name,
      )
    }
    guard request_context_count <= 1 else {
      return Err(
        "only one request_context parameter is supported by #proton.command: " +
        command.function_name,
      )
    }
    if command.has_request_context {
      guard command.is_async && command.returns_result else {
        return Err(
          "request_context parameter requires async Result command in #proton.command: " +
          command.function_name,
        )
      }
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
  let names : Map[String, Bool] = Map([])
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
