///|
async fn read_moon_ext_codegen_config_file(path : String) -> (String, String) {
  let text = @async_fs.read_file(path).text() catch {
    error =>
      raise CodegenInputError::InputRead(
        path~,
        detail=@debug.render(@debug.to_repr(error)),
      )
  }
  read_moon_ext_codegen_config(path, text)
}

///|
pub async fn read_moon_ext_identity(path : String) -> (String, String) {
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
fn mbt_string(s : String) -> String {
  "\"" + escape_mbt_string(s) + "\""
}

///|
fn escape_mbt_string(s : String) -> String {
  let builder = StringBuilder::new()
  for _, ch in s {
    match ch {
      '"' => builder.write_string("\\\"")
      '\\' => builder.write_string("\\\\")
      '\n' => builder.write_string("\\n")
      '\r' => builder.write_string("\\r")
      '\t' => builder.write_string("\\t")
      _ => builder.write_char(ch)
    }
  }
  builder.to_string()
}
