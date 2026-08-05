///|
fn[T, E : Error] try_result_protocol_typed_typed_decode_wbtest(
  f : () -> T raise E,
) -> Result[T, E] {
  try f() catch {
    e => Err(e)
  } noraise {
    value => Ok(value)
  }
}

///|
test "typed parameter helpers decode required and optional scalars" {
  let fields : Map[String, Json] = {
    "string": "value",
    "integer": 7,
    "number": 7.5,
    "true": true,
    "false": false,
    "null": null,
  }
  inspect(
    typed_required_string("Runtime.evaluate", fields, "string", "string"),
    content="value",
  )
  guard typed_optional_string("Runtime.evaluate", fields, "string", "string")
    is Some("value") else {
    fail("expected optional string")
  }
  assert_true(
    typed_optional_string("Runtime.evaluate", fields, "null", "string") is None,
  )
  inspect(
    typed_required_int("Runtime.evaluate", fields, "integer", "integer"),
    content="7",
  )
  guard typed_optional_int("Runtime.evaluate", fields, "integer", "integer")
    is Some(7) else {
    fail("expected optional integer")
  }
  inspect(
    typed_required_double("Runtime.evaluate", fields, "number", "number"),
    content="7.5",
  )
  guard typed_optional_double("Runtime.evaluate", fields, "number", "number")
    is Some(7.5) else {
    fail("expected optional number")
  }
  inspect(
    typed_required_bool("Runtime.evaluate", fields, "true", "boolean"),
    content="true",
  )
  inspect(
    typed_required_bool("Runtime.evaluate", fields, "false", "boolean"),
    content="false",
  )
  guard typed_optional_bool("Runtime.evaluate", fields, "true", "boolean")
    is Some(true) else {
    fail("expected optional bool")
  }
  guard typed_optional_bool("Runtime.evaluate", fields, "false", "boolean")
    is Some(false) else {
    fail("expected optional false")
  }
  assert_true(typed_optional_json(fields, "missing") is None)
  assert_true(
    typed_optional_int("Runtime.evaluate", fields, "missing", "integer") is None,
  )
  assert_true(
    typed_optional_double("Runtime.evaluate", fields, "missing", "number")
    is None,
  )
  assert_true(
    typed_optional_bool("Runtime.evaluate", fields, "missing", "boolean")
    is None,
  )
}

///|
test "typed parameter helpers reject bad shapes and numeric types" {
  let not_object : Result[Map[String, Json], Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_json_fields("Runtime.evaluate", [])
    },
  )
  guard not_object
    is Err(
      @protocol.ProtocolSchemaError::ExpectedParamsObject("Runtime.evaluate")
    ) else {
    fail("expected params object error")
  }

  let fields : Map[String, Json] = {
    "fraction": 1.5,
    "string": "value",
    "array": [1, "two"],
  }
  let missing : Result[Json, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_required_json("Runtime.evaluate", fields, "missing")
    },
  )
  guard missing
    is Err(
      @protocol.ProtocolSchemaError::MissingParameter(
        "Runtime.evaluate",
        "missing"
      )
    ) else {
    fail("expected missing parameter")
  }
  let bad_int : Result[Int, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_required_int("Runtime.evaluate", fields, "fraction", "integer")
    },
  )
  guard bad_int
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "fraction",
        "integer"
      )
    ) else {
    fail("expected invalid integer")
  }
  let bad_int_shape : Result[Int, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_required_int("Runtime.evaluate", fields, "string", "integer")
    },
  )
  guard bad_int_shape
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "string",
        "integer"
      )
    ) else {
    fail("expected invalid integer shape")
  }
  let bad_optional_int : Result[Int?, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_optional_int("Runtime.evaluate", fields, "fraction", "integer")
    },
  )
  guard bad_optional_int
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "fraction",
        "integer"
      )
    ) else {
    fail("expected invalid optional integer")
  }
  let bad_optional_int_shape : Result[Int?, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_optional_int("Runtime.evaluate", fields, "string", "integer")
    },
  )
  guard bad_optional_int_shape
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "string",
        "integer"
      )
    ) else {
    fail("expected invalid optional integer shape")
  }
  let array = typed_param_array(
    "Runtime.evaluate",
    fields["array"],
    "items",
    "array",
  )
  inspect(array.length(), content="2")
  inspect(
    typed_array_string("Runtime.evaluate", "items", "string", array[1]),
    content="two",
  )
  inspect(
    typed_array_int("Runtime.evaluate", "items", "integer", array[0]),
    content="1",
  )
  inspect(
    typed_array_double("Runtime.evaluate", "items", "number", array[0]),
    content="1",
  )
  let bad_array_item : Result[String, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_array_string("Runtime.evaluate", "items", "string", array[0])
    },
  )
  guard bad_array_item
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "items",
        "string"
      )
    ) else {
    fail("expected invalid array string")
  }
  let bad_required_string : Result[String, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_required_string("Runtime.evaluate", fields, "fraction", "string")
    },
  )
  guard bad_required_string
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "fraction",
        "string"
      )
    ) else {
    fail("expected invalid required string")
  }
  let bad_optional_string : Result[String?, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_optional_string("Runtime.evaluate", fields, "fraction", "string")
    },
  )
  guard bad_optional_string
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "fraction",
        "string"
      )
    ) else {
    fail("expected invalid optional string")
  }
  let bad_required_double : Result[Double, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_required_double("Runtime.evaluate", fields, "string", "number")
    },
  )
  guard bad_required_double
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "string",
        "number"
      )
    ) else {
    fail("expected invalid required double")
  }
  let bad_optional_double : Result[Double?, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_optional_double("Runtime.evaluate", fields, "string", "number")
    },
  )
  guard bad_optional_double
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "string",
        "number"
      )
    ) else {
    fail("expected invalid optional double")
  }
  let bad_required_bool : Result[Bool, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_required_bool("Runtime.evaluate", fields, "string", "boolean")
    },
  )
  guard bad_required_bool
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "string",
        "boolean"
      )
    ) else {
    fail("expected invalid required bool")
  }
  let bad_optional_bool : Result[Bool?, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_optional_bool("Runtime.evaluate", fields, "string", "boolean")
    },
  )
  guard bad_optional_bool
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "string",
        "boolean"
      )
    ) else {
    fail("expected invalid optional bool")
  }
  let bad_param_array : Result[Array[Json], Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_param_array("Runtime.evaluate", fields["string"], "items", "array")
    },
  )
  guard bad_param_array
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "items",
        "array"
      )
    ) else {
    fail("expected invalid param array")
  }
  let bad_array_int : Result[Int, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_array_int(
        "Runtime.evaluate",
        "items",
        "integer",
        fields["fraction"],
      )
    },
  )
  guard bad_array_int
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "items",
        "integer"
      )
    ) else {
    fail("expected invalid array int")
  }
  let bad_array_int_shape : Result[Int, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_array_int("Runtime.evaluate", "items", "integer", fields["string"])
    },
  )
  guard bad_array_int_shape
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "items",
        "integer"
      )
    ) else {
    fail("expected invalid array int shape")
  }
  let bad_array_double : Result[Double, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_array_double(
        "Runtime.evaluate",
        "items",
        "number",
        fields["string"],
      )
    },
  )
  guard bad_array_double
    is Err(
      @protocol.ProtocolSchemaError::InvalidParameterType(
        "Runtime.evaluate",
        "items",
        "number"
      )
    ) else {
    fail("expected invalid array double")
  }
}

///|
test "typed result helpers decode required and optional values" {
  let fields : Map[String, Json] = {
    "string": "value",
    "integer": 3,
    "number": 3.5,
    "true": true,
    "false": false,
    "array": ["one", 2, 3.5],
    "null": null,
  }
  let result_fields = typed_result_fields("Page.navigate", Json::object(fields))
  inspect(
    typed_required_result_string(
      "Page.navigate", result_fields, "string", "string",
    ),
    content="value",
  )
  guard typed_optional_result_string(
      "Page.navigate", result_fields, "string", "string",
    )
    is Some("value") else {
    fail("expected optional result string")
  }
  assert_true(
    typed_optional_result_string(
      "Page.navigate", result_fields, "null", "string",
    )
    is None,
  )
  inspect(
    typed_required_result_int(
      "Page.navigate", result_fields, "integer", "integer",
    ),
    content="3",
  )
  guard typed_optional_result_int(
      "Page.navigate", result_fields, "integer", "integer",
    )
    is Some(3) else {
    fail("expected optional result integer")
  }
  inspect(
    typed_required_result_double(
      "Page.navigate", result_fields, "number", "number",
    ),
    content="3.5",
  )
  inspect(
    typed_required_result_bool(
      "Page.navigate", result_fields, "true", "boolean",
    ),
    content="true",
  )
  inspect(
    typed_required_result_bool(
      "Page.navigate", result_fields, "false", "boolean",
    ),
    content="false",
  )
  guard typed_optional_result_bool(
      "Page.navigate", result_fields, "true", "boolean",
    )
    is Some(true) else {
    fail("expected optional result bool")
  }
  assert_true(typed_optional_result_json(result_fields, "missing") is None)
  assert_true(
    typed_optional_result_int(
      "Page.navigate", result_fields, "missing", "integer",
    )
    is None,
  )
  assert_true(
    typed_optional_result_bool(
      "Page.navigate", result_fields, "missing", "boolean",
    )
    is None,
  )

  let array = typed_result_array(
    "Page.navigate",
    result_fields["array"],
    "items",
    "array",
  )
  inspect(
    typed_result_array_string("Page.navigate", "items", "string", array[0]),
    content="one",
  )
  inspect(
    typed_result_array_int("Page.navigate", "items", "integer", array[1]),
    content="2",
  )
}

///|
test "typed result helpers reject bad shapes and return types" {
  let bad_shape : Result[Map[String, Json], Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_result_fields("Page.navigate", [])
    },
  )
  guard bad_shape
    is Err(@protocol.ProtocolSchemaError::ExpectedResultObject("Page.navigate")) else {
    fail("expected result object")
  }
  let fields : Map[String, Json] = {
    "fraction": 1.5,
    "string": "value",
    "bad_array": "items",
  }
  let missing : Result[Json, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_required_result_json("Page.navigate", fields, "missing")
    },
  )
  guard missing
    is Err(
      @protocol.ProtocolSchemaError::MissingReturn("Page.navigate", "missing")
    ) else {
    fail("expected missing return")
  }
  let bad_int : Result[Int, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_required_result_int("Page.navigate", fields, "fraction", "integer")
    },
  )
  guard bad_int
    is Err(
      @protocol.ProtocolSchemaError::InvalidReturnType(
        "Page.navigate",
        "fraction",
        "integer"
      )
    ) else {
    fail("expected invalid return integer")
  }
  let bad_int_shape : Result[Int, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_required_result_int("Page.navigate", fields, "string", "integer")
    },
  )
  guard bad_int_shape
    is Err(
      @protocol.ProtocolSchemaError::InvalidReturnType(
        "Page.navigate",
        "string",
        "integer"
      )
    ) else {
    fail("expected invalid return integer shape")
  }
  let bad_optional_int : Result[Int?, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_optional_result_int("Page.navigate", fields, "fraction", "integer")
    },
  )
  guard bad_optional_int
    is Err(
      @protocol.ProtocolSchemaError::InvalidReturnType(
        "Page.navigate",
        "fraction",
        "integer"
      )
    ) else {
    fail("expected invalid optional return integer")
  }
  let bad_optional_int_shape : Result[Int?, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_optional_result_int("Page.navigate", fields, "string", "integer")
    },
  )
  guard bad_optional_int_shape
    is Err(
      @protocol.ProtocolSchemaError::InvalidReturnType(
        "Page.navigate",
        "string",
        "integer"
      )
    ) else {
    fail("expected invalid optional return integer shape")
  }
  let bad_optional_string : Result[String?, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_optional_result_string(
        "Page.navigate", fields, "fraction", "string",
      )
    },
  )
  guard bad_optional_string
    is Err(
      @protocol.ProtocolSchemaError::InvalidReturnType(
        "Page.navigate",
        "fraction",
        "string"
      )
    ) else {
    fail("expected invalid optional return string")
  }
  let bad_array : Result[Array[Json], Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_result_array("Page.navigate", fields["bad_array"], "items", "array")
    },
  )
  guard bad_array
    is Err(
      @protocol.ProtocolSchemaError::InvalidReturnType(
        "Page.navigate",
        "items",
        "array"
      )
    ) else {
    fail("expected invalid result array")
  }
  let bad_array_int : Result[Int, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_result_array_int(
        "Page.navigate",
        "items",
        "integer",
        fields["fraction"],
      )
    },
  )
  guard bad_array_int
    is Err(
      @protocol.ProtocolSchemaError::InvalidReturnType(
        "Page.navigate",
        "items",
        "integer"
      )
    ) else {
    fail("expected invalid result array integer")
  }
  let bad_array_int_shape : Result[Int, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_result_array_int(
        "Page.navigate",
        "items",
        "integer",
        fields["string"],
      )
    },
  )
  guard bad_array_int_shape
    is Err(
      @protocol.ProtocolSchemaError::InvalidReturnType(
        "Page.navigate",
        "items",
        "integer"
      )
    ) else {
    fail("expected invalid result array integer shape")
  }
  let bad_required_string : Result[String, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_required_result_string(
        "Page.navigate", fields, "fraction", "string",
      )
    },
  )
  guard bad_required_string
    is Err(
      @protocol.ProtocolSchemaError::InvalidReturnType(
        "Page.navigate",
        "fraction",
        "string"
      )
    ) else {
    fail("expected invalid required return string")
  }
  let bad_required_double : Result[Double, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_required_result_double("Page.navigate", fields, "string", "number")
    },
  )
  guard bad_required_double
    is Err(
      @protocol.ProtocolSchemaError::InvalidReturnType(
        "Page.navigate",
        "string",
        "number"
      )
    ) else {
    fail("expected invalid required return double")
  }
  let bad_required_bool : Result[Bool, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_required_result_bool("Page.navigate", fields, "string", "boolean")
    },
  )
  guard bad_required_bool
    is Err(
      @protocol.ProtocolSchemaError::InvalidReturnType(
        "Page.navigate",
        "string",
        "boolean"
      )
    ) else {
    fail("expected invalid required return bool")
  }
  let bad_optional_bool : Result[Bool?, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_optional_result_bool("Page.navigate", fields, "string", "boolean")
    },
  )
  guard bad_optional_bool
    is Err(
      @protocol.ProtocolSchemaError::InvalidReturnType(
        "Page.navigate",
        "string",
        "boolean"
      )
    ) else {
    fail("expected invalid optional return bool")
  }
  let bad_array_string : Result[String, Error] = try_result_protocol_typed_typed_decode_wbtest(() => {
      typed_result_array_string(
        "Page.navigate",
        "items",
        "string",
        fields["fraction"],
      )
    },
  )
  guard bad_array_string
    is Err(
      @protocol.ProtocolSchemaError::InvalidReturnType(
        "Page.navigate",
        "items",
        "string"
      )
    ) else {
    fail("expected invalid result array string")
  }
}
