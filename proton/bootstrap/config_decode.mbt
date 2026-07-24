///|
/// Reads and decodes a required string field from a JSON object.
fn required_string_field(
  object : Map[String, Json],
  key : String,
  label : String,
) -> String raise BootstrapError {
  decode_string(required_field(object, key, label), label)
}

///|
/// Reads and decodes a required integer field from a JSON object.
fn required_int_field(
  object : Map[String, Json],
  key : String,
  label : String,
) -> Int raise BootstrapError {
  decode_int(required_field(object, key, label), label)
}

///|
/// Returns a required field or a descriptive missing-field error.
fn required_field(
  object : Map[String, Json],
  key : String,
  label : String,
) -> Json raise BootstrapError {
  match object.get(key) {
    Some(value) => value
    None => raise MissingField(path=label)
  }
}

///|
/// Returns an optional raw JSON field from an object.
fn optional_field(object : Map[String, Json], key : String) -> Json? {
  object.get(key)
}

///|
/// Decodes an optional string field while preserving `None`.
fn decode_optional_string(
  json : Json?,
  label : String,
) -> String? raise BootstrapError {
  match json {
    None => None
    Some(json) => Some(decode_string(json, label))
  }
}

///|
/// Decodes an optional integer field while preserving `None`.
fn decode_optional_int(
  json : Json?,
  label : String,
) -> Int? raise BootstrapError {
  match json {
    None => None
    Some(json) => Some(decode_int(json, label))
  }
}

///|
/// Decodes a JSON value as a string with a labeled error message.
fn decode_string(json : Json, label : String) -> String raise BootstrapError {
  @json.from_json(json) catch {
    error =>
      raise InvalidJson(
        context=label,
        detail="expected string: " + error.to_string(),
      )
  }
}

///|
/// Decodes a JSON value as an integer with a labeled error message.
fn decode_int(json : Json, label : String) -> Int raise BootstrapError {
  @json.from_json(json) catch {
    error =>
      raise InvalidJson(
        context=label,
        detail="expected int: " + error.to_string(),
      )
  }
}

///|
/// Ensures a JSON value is an object before continuing config decoding.
fn expect_object(
  json : Json,
  label : String,
) -> Map[String, Json] raise BootstrapError {
  match json {
    Object(object) => object
    _ => raise InvalidField(path=label, expectation="must be an object")
  }
}

///|
fn[Value] required_built_field(
  object : Map[String, Json],
  key : String,
  label : String,
  build : (Json) -> Value raise BootstrapError,
) -> Value raise BootstrapError {
  build(required_field(object, key, label))
}
