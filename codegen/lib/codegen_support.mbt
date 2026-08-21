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
      | "moonbit_import_path"
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
