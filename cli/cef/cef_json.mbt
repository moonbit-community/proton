///|
fn read_json_file(path : String) -> Json raise CefRuntimeError {
  let text = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    err => raise ManifestRead(path~, detail=@debug.render(@debug.to_repr(err)))
  }
  @json.parse(text) catch {
    err =>
      raise ManifestSyntax(path~, detail=@debug.render(@debug.to_repr(err)))
  }
}

///|
fn json_string_field(
  json : Json,
  field : String,
  label : String,
) -> String raise CefRuntimeError {
  match json {
    Object(object) =>
      match object.get(field) {
        Some(String(value)) => value
        _ => raise ManifestField(path=label, field~)
      }
    _ => raise ManifestShape(path=label, detail="root must be a JSON object")
  }
}
