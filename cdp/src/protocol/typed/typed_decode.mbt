///|
// Require generated event or parameter JSON to be an object.
fn typed_json_fields(
  method_name : String,
  params : Json,
) -> Map[String, Json] raise @protocol.ProtocolSchemaError {
  guard params is Object(fields) else {
    raise ExpectedParamsObject(method_name)
  }
  fields
}

///|
// Read a required generated parameter field as raw JSON.
fn typed_required_json(
  method_name : String,
  fields : Map[String, Json],
  name : String,
) -> Json raise @protocol.ProtocolSchemaError {
  match fields.get(name) {
    Some(value) => value
    None => raise MissingParameter(method_name, name)
  }
}

///|
// Read an optional generated parameter field as raw JSON.
fn typed_optional_json(fields : Map[String, Json], name : String) -> Json? {
  match fields.get(name) {
    Some(Null) | None => None
    Some(value) => Some(value)
  }
}

///|
// Decode a required generated string parameter.
fn typed_required_string(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> String raise @protocol.ProtocolSchemaError {
  match typed_required_json(method_name, fields, name) {
    String(value) => value
    _ => raise InvalidParameterType(method_name, name, expected)
  }
}

///|
// Decode an optional generated string parameter.
fn typed_optional_string(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> String? raise @protocol.ProtocolSchemaError {
  match typed_optional_json(fields, name) {
    Some(String(value)) => Some(value)
    Some(_) => raise InvalidParameterType(method_name, name, expected)
    None => None
  }
}

///|
// Decode a required generated integer parameter.
fn typed_required_int(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Int raise @protocol.ProtocolSchemaError {
  match typed_required_json(method_name, fields, name) {
    Number(value, ..) => {
      let int = value.to_int()
      if int.to_double() == value {
        int
      } else {
        raise InvalidParameterType(method_name, name, expected)
      }
    }
    _ => raise InvalidParameterType(method_name, name, expected)
  }
}

///|
// Decode an optional generated integer parameter.
fn typed_optional_int(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Int? raise @protocol.ProtocolSchemaError {
  match typed_optional_json(fields, name) {
    Some(Number(value, ..)) => {
      let int = value.to_int()
      if int.to_double() == value {
        Some(int)
      } else {
        raise InvalidParameterType(method_name, name, expected)
      }
    }
    Some(_) => raise InvalidParameterType(method_name, name, expected)
    None => None
  }
}

///|
// Decode a required generated number parameter.
fn typed_required_double(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Double raise @protocol.ProtocolSchemaError {
  match typed_required_json(method_name, fields, name) {
    Number(value, ..) => value
    _ => raise InvalidParameterType(method_name, name, expected)
  }
}

///|
// Decode an optional generated number parameter.
fn typed_optional_double(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Double? raise @protocol.ProtocolSchemaError {
  match typed_optional_json(fields, name) {
    Some(Number(value, ..)) => Some(value)
    Some(_) => raise InvalidParameterType(method_name, name, expected)
    None => None
  }
}

///|
// Decode a required generated boolean parameter.
fn typed_required_bool(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Bool raise @protocol.ProtocolSchemaError {
  match typed_required_json(method_name, fields, name) {
    True => true
    False => false
    _ => raise InvalidParameterType(method_name, name, expected)
  }
}

///|
// Decode an optional generated boolean parameter.
fn typed_optional_bool(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Bool? raise @protocol.ProtocolSchemaError {
  match typed_optional_json(fields, name) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(_) => raise InvalidParameterType(method_name, name, expected)
    None => None
  }
}

///|
// Require a generated array parameter.
fn typed_param_array(
  method_name : String,
  value : Json,
  name : String,
  expected : String,
) -> Array[Json] raise @protocol.ProtocolSchemaError {
  match value {
    Array(items) => items
    _ => raise InvalidParameterType(method_name, name, expected)
  }
}

///|
// Decode one generated array item as a string parameter.
fn typed_array_string(
  method_name : String,
  name : String,
  expected : String,
  value : Json,
) -> String raise @protocol.ProtocolSchemaError {
  match value {
    String(inner) => inner
    _ => raise InvalidParameterType(method_name, name, expected)
  }
}

///|
// Decode one generated array item as an integer parameter.
fn typed_array_int(
  method_name : String,
  name : String,
  expected : String,
  value : Json,
) -> Int raise @protocol.ProtocolSchemaError {
  match value {
    Number(inner, ..) => {
      let int = inner.to_int()
      if int.to_double() == inner {
        int
      } else {
        raise InvalidParameterType(method_name, name, expected)
      }
    }
    _ => raise InvalidParameterType(method_name, name, expected)
  }
}

///|
// Decode one generated array item as a number parameter.
fn typed_array_double(
  method_name : String,
  name : String,
  expected : String,
  value : Json,
) -> Double raise @protocol.ProtocolSchemaError {
  match value {
    Number(inner, ..) => inner
    _ => raise InvalidParameterType(method_name, name, expected)
  }
}

///|
// Require generated command result JSON to be an object.
fn typed_result_fields(
  method_name : String,
  result : Json,
) -> Map[String, Json] raise @protocol.ProtocolSchemaError {
  guard result is Object(fields) else {
    raise ExpectedResultObject(method_name)
  }
  fields
}

///|
// Read a required generated result field as raw JSON.
fn typed_required_result_json(
  method_name : String,
  fields : Map[String, Json],
  name : String,
) -> Json raise @protocol.ProtocolSchemaError {
  match fields.get(name) {
    Some(value) => value
    None => raise MissingReturn(method_name, name)
  }
}

///|
// Read an optional generated result field as raw JSON.
fn typed_optional_result_json(
  fields : Map[String, Json],
  name : String,
) -> Json? {
  match fields.get(name) {
    Some(Null) | None => None
    Some(value) => Some(value)
  }
}

///|
// Decode a required generated string result field.
fn typed_required_result_string(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> String raise @protocol.ProtocolSchemaError {
  match typed_required_result_json(method_name, fields, name) {
    String(value) => value
    _ => raise InvalidReturnType(method_name, name, expected)
  }
}

///|
// Decode an optional generated string result field.
fn typed_optional_result_string(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> String? raise @protocol.ProtocolSchemaError {
  match typed_optional_result_json(fields, name) {
    Some(String(value)) => Some(value)
    Some(_) => raise InvalidReturnType(method_name, name, expected)
    None => None
  }
}

///|
// Require a generated array result field.
fn typed_result_array(
  method_name : String,
  value : Json,
  name : String,
  expected : String,
) -> Array[Json] raise @protocol.ProtocolSchemaError {
  match value {
    Array(items) => items
    _ => raise InvalidReturnType(method_name, name, expected)
  }
}

///|
// Decode one generated array item as a string result value.
fn typed_result_array_string(
  method_name : String,
  name : String,
  expected : String,
  value : Json,
) -> String raise @protocol.ProtocolSchemaError {
  match value {
    String(inner) => inner
    _ => raise InvalidReturnType(method_name, name, expected)
  }
}

///|
// Decode one generated array item as an integer result value.
fn typed_result_array_int(
  method_name : String,
  name : String,
  expected : String,
  value : Json,
) -> Int raise @protocol.ProtocolSchemaError {
  match value {
    Number(inner, ..) => {
      let int = inner.to_int()
      if int.to_double() == inner {
        int
      } else {
        raise InvalidReturnType(method_name, name, expected)
      }
    }
    _ => raise InvalidReturnType(method_name, name, expected)
  }
}

///|
// Decode a required generated integer result field.
fn typed_required_result_int(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Int raise @protocol.ProtocolSchemaError {
  match typed_required_result_json(method_name, fields, name) {
    Number(value, ..) => {
      let int = value.to_int()
      if int.to_double() == value {
        int
      } else {
        raise InvalidReturnType(method_name, name, expected)
      }
    }
    _ => raise InvalidReturnType(method_name, name, expected)
  }
}

///|
// Decode an optional generated integer result field.
fn typed_optional_result_int(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Int? raise @protocol.ProtocolSchemaError {
  match typed_optional_result_json(fields, name) {
    Some(Number(value, ..)) => {
      let int = value.to_int()
      if int.to_double() == value {
        Some(int)
      } else {
        raise InvalidReturnType(method_name, name, expected)
      }
    }
    Some(_) => raise InvalidReturnType(method_name, name, expected)
    None => None
  }
}

///|
// Decode a required generated number result field.
fn typed_required_result_double(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Double raise @protocol.ProtocolSchemaError {
  match typed_required_result_json(method_name, fields, name) {
    Number(value, ..) => value
    _ => raise InvalidReturnType(method_name, name, expected)
  }
}

///|
// Decode a required generated boolean result field.
fn typed_required_result_bool(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Bool raise @protocol.ProtocolSchemaError {
  match typed_required_result_json(method_name, fields, name) {
    True => true
    False => false
    _ => raise InvalidReturnType(method_name, name, expected)
  }
}

///|
// Decode an optional generated boolean result field.
fn typed_optional_result_bool(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Bool? raise @protocol.ProtocolSchemaError {
  match typed_optional_result_json(fields, name) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(_) => raise InvalidReturnType(method_name, name, expected)
    None => None
  }
}
