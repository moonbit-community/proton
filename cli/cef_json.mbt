///|
fn read_json_file(path : String) -> Result[Json, CliError] {
  let text = @mbfs.read_file_to_string(path, encoding="utf8") catch {
    err =>
      return Err(
        CliError::CommandError(
          "Failed to read " + path + ": " + @debug.render(@debug.to_repr(err)),
        ),
      )
  }
  try @json.parse(text) catch {
    err =>
      Err(
        CliError::CommandError(
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
) -> Result[String, CliError] {
  match json {
    Object(object) =>
      match object.get(field) {
        Some(String(value)) => Ok(value)
        _ =>
          Err(CliError::CommandError(label + " missing string field: " + field))
      }
    _ => Err(CliError::CommandError(label + " must be a JSON object"))
  }
}
