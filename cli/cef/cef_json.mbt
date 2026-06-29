///|
fn read_json_file(path : String) -> Result[Json, CefError] {
  let text = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    err =>
      return Err(
        CefError::CommandError(
          "Failed to read " + path + ": " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  try @json.parse(text) catch {
    err =>
      Err(
        CefError::CommandError(
          "Failed to parse " + path + ": " + @debug.render(@debug.to_repr(err)),
        ),
      )
  } noraise {
    json => Ok(json)
  }
}

///|
fn json_string_field(
  json : Json,
  field : String,
  label : String,
) -> Result[String, CefError] {
  match json {
    Object(object) =>
      match object.get(field) {
        Some(String(value)) => Ok(value)
        _ =>
          Err(CefError::CommandError(label + " missing string field: " + field))
      }
    _ => Err(CefError::CommandError(label + " must be a JSON object"))
  }
}
