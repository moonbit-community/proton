///|
async fn read_proton_ext_codegen_config_file(path : String) -> (String, String) {
  let text = @async_fs.read_file(path).text() catch {
    error =>
      raise CodegenInputError::InputRead(
        path~,
        detail=@debug.render(Repr(error)),
      )
  }
  read_proton_ext_codegen_config(path, text)
}

///|
pub async fn read_proton_ext_identity(path : String) -> (String, String) {
  read_proton_ext_codegen_config_file(path)
}

///|
fn read_proton_ext_codegen_config(
  path : String,
  text : String,
) -> (String, String) raise {
  let json = @json.parse(text) catch {
    error =>
      raise CodegenMetadataFileError::Syntax(
        path~,
        diagnostics=error.to_string(),
      )
  }
  try {
    match json {
      Object(fields) => read_proton_ext_codegen_fields(fields)
      _ => raise CodegenMetadataError::InvalidRoot
    }
  } catch {
    error => raise CodegenMetadataFileError::Invalid(path~, error~)
  }
}

///|
fn read_proton_ext_codegen_fields(
  fields : Map[String, Json],
) -> (String, String) raise CodegenMetadataError {
  validate_proton_ext_codegen_fields(fields)
  (
    proton_ext_codegen_required_string(fields, "id"),
    proton_ext_codegen_required_string(fields, "namespace"),
  )
}

///|
fn validate_proton_ext_codegen_fields(
  fields : Map[String, Json],
) -> Unit raise CodegenMetadataError {
  for key, value in fields {
    match key {
      "id"
      | "namespace"
      | "version"
      | "display_name"
      | "description"
      | "license"
      | "repository"
      | "readme" =>
        match value {
          String(_) => ()
          _ => raise InvalidType(field=key, expected="a string")
        }
      "package" =>
        match value {
          String(value) => validate_npm_package_name(value)
          _ => raise InvalidType(field="package", expected="a string")
        }
      "keywords" | "platforms" | "dependencies" =>
        match value {
          Array(_) => ()
          _ => raise InvalidType(field=key, expected="an array")
        }
      other => raise UnknownField(field=other)
    }
  }
}

///|
fn proton_ext_codegen_required_string(
  fields : Map[String, Json],
  key : String,
) -> String raise CodegenMetadataError {
  match fields.get(key) {
    Some(String(value)) => value
    Some(_) => raise InvalidType(field=key, expected="a string")
    None => raise MissingField(field=key)
  }
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
  let native_path : @mbpath.Path = path
  native_path.dirname().to_string()
}

///|
fn path_join(dir : String, name : String) -> String {
  let native_dir : @mbpath.Path = dir
  native_dir.join(name).to_string()
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
