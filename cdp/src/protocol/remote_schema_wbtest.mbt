///|
fn[T, E : Error] try_result_protocol_remote_schema_wbtest(
  f : () -> T raise E,
) -> Result[T, E] {
  try f() catch {
    e => Err(e)
  } noraise {
    value => Ok(value)
  }
}

///|
test "remote schema private helpers reject malformed primitive fields" {
  let bad_object : Result[Map[String, Json], Error] = try_result_protocol_remote_schema_wbtest(() => {
      json_object_fields([], "protocol")
    },
  )
  guard bad_object is Err(ProtocolSchemaDiffError::ExpectedObject("protocol")) else {
    fail("expected object error")
  }

  let missing : Result[Json, Error] = try_result_protocol_remote_schema_wbtest(() => {
    required_json({}, "version")
  })
  guard missing is Err(ProtocolSchemaDiffError::MissingField("version")) else {
    fail("expected missing field")
  }

  let bad_array : Result[Array[Json], Error] = try_result_protocol_remote_schema_wbtest(() => {
      json_array({}, "domains")
    },
  )
  guard bad_array is Err(ProtocolSchemaDiffError::InvalidField("domains")) else {
    fail("expected invalid array")
  }

  let bad_optional_array : Result[Array[Json], Error] = try_result_protocol_remote_schema_wbtest(() => {
      optional_json_array({ "items": {} }, "items")
    },
  )
  guard bad_optional_array
    is Err(ProtocolSchemaDiffError::InvalidField("items")) else {
    fail("expected invalid optional array")
  }

  let missing_string : Result[String, Error] = try_result_protocol_remote_schema_wbtest(() => {
      schema_required_string({}, "domain")
    },
  )
  guard missing_string is Err(ProtocolSchemaDiffError::MissingField("domain")) else {
    fail("expected missing string")
  }

  let bad_string : Result[String, Error] = try_result_protocol_remote_schema_wbtest(() => {
      schema_required_string({ "domain": false }, "domain")
    },
  )
  guard bad_string is Err(ProtocolSchemaDiffError::InvalidField("domain")) else {
    fail("expected invalid string")
  }

  let bad_optional_string : Result[String?, Error] = try_result_protocol_remote_schema_wbtest(() => {
      schema_optional_string({ "$ref": false }, "$ref")
    },
  )
  guard bad_optional_string
    is Err(ProtocolSchemaDiffError::InvalidField("$ref")) else {
    fail("expected invalid optional string")
  }

  let bad_bool : Result[Bool, Error] = try_result_protocol_remote_schema_wbtest(() => {
      optional_bool({ "experimental": "yes" }, "experimental")
    },
  )
  guard bad_bool is Err(ProtocolSchemaDiffError::InvalidField("experimental")) else {
    fail("expected invalid optional bool")
  }
}

///|
test "remote schema private helpers cover kind and enum edge cases" {
  inspect(value_kind({}), content="any")

  let bad_items : Result[String, Error] = try_result_protocol_remote_schema_wbtest(() => {
      array_item_kind({ "items": false })
    },
  )
  guard bad_items is Err(ProtocolSchemaDiffError::InvalidField("items")) else {
    fail("expected invalid array items")
  }

  let bad_enum : Result[Array[String], Error] = try_result_protocol_remote_schema_wbtest(() => {
      string_values([false])
    },
  )
  guard bad_enum is Err(ProtocolSchemaDiffError::InvalidField("enum")) else {
    fail("expected invalid enum item")
  }

  let bundled : ProtocolType = {
    protocol: "browser",
    domain: "Page",
    name: "FrameId",
    kind: "string",
    property_count: 0,
    enum_count: 0,
    properties: [],
    property_details: [],
    enum_values: [],
    experimental: false,
    deprecated: false,
  }
  let remote : ProtocolType = {
    protocol: "browser",
    domain: "Page",
    name: "FrameId",
    kind: "integer",
    property_count: 0,
    enum_count: 0,
    properties: [],
    property_details: [],
    enum_values: [],
    experimental: false,
    deprecated: false,
  }
  assert_true(
    type_diff_details(bundled, remote).contains(
      "kind local=string remote=integer",
    ),
  )
}

///|
test "protocol schema diff reports bundled schema as compatible" {
  let report = protocol_schema_diff(bundled_remote_schema())
  assert_true(report.compatible)
  inspect(report.local_only_domains.length(), content="0")
  inspect(report.local_only_commands.length(), content="0")
  inspect(report.changed_commands.length(), content="0")
  inspect(report.local_only_events.length(), content="0")
  inspect(report.changed_events.length(), content="0")
  inspect(report.local_only_types.length(), content="0")
  inspect(report.changed_types.length(), content="0")
}

///|
fn bundled_remote_schema() -> Json {
  let manifest = protocol_manifest()
  let commands_by_domain : Map[String, Array[ProtocolCommand]] = {}
  for command in protocol_commands() {
    let items = commands_by_domain.get(command.domain).unwrap_or([])
    items.push(command)
    commands_by_domain[command.domain] = items
  }
  let events_by_domain : Map[String, Array[ProtocolEvent]] = {}
  for event in protocol_events() {
    let items = events_by_domain.get(event.domain).unwrap_or([])
    items.push(event)
    events_by_domain[event.domain] = items
  }
  let types_by_domain : Map[String, Array[ProtocolType]] = {}
  for type_ in protocol_types() {
    let items = types_by_domain.get(type_.domain).unwrap_or([])
    items.push(type_)
    types_by_domain[type_.domain] = items
  }
  {
    "version": {
      "major": manifest.version.major,
      "minor": manifest.version.minor,
    },
    "domains": manifest.domains.map(domain => {
      let fields : Map[String, Json] = {
        "domain": domain.domain,
        "commands": commands_by_domain
        .get(domain.domain)
        .unwrap_or([])
        .map(command_to_remote_json),
        "events": events_by_domain
        .get(domain.domain)
        .unwrap_or([])
        .map(event_to_remote_json),
        "types": types_by_domain
        .get(domain.domain)
        .unwrap_or([])
        .map(type_to_remote_json),
      }
      if domain.experimental {
        fields["experimental"] = true
      }
      if domain.deprecated {
        fields["deprecated"] = true
      }
      Json::object(fields)
    }),
  }
}

///|
fn command_to_remote_json(command : ProtocolCommand) -> Json {
  let fields : Map[String, Json] = {
    "name": command.name,
    "parameters": command.parameter_details.map(field_to_remote_json),
    "returns": command.return_details.map(field_to_remote_json),
  }
  if command.experimental {
    fields["experimental"] = true
  }
  if command.deprecated {
    fields["deprecated"] = true
  }
  Json::object(fields)
}

///|
fn event_to_remote_json(event : ProtocolEvent) -> Json {
  let fields : Map[String, Json] = {
    "name": event.name,
    "parameters": event.parameter_details.map(field_to_remote_json),
  }
  if event.experimental {
    fields["experimental"] = true
  }
  if event.deprecated {
    fields["deprecated"] = true
  }
  Json::object(fields)
}

///|
fn type_to_remote_json(type_ : ProtocolType) -> Json {
  let fields : Map[String, Json] = {
    "id": type_.name,
    "properties": type_.property_details.map(field_to_remote_json),
    "enum": type_.enum_values.map(value => Json::string(value)),
  }
  match type_.kind {
    "ref" => fields["$ref"] = "Unknown"
    "any" => ()
    kind => fields["type"] = Json::string(kind)
  }
  if type_.experimental {
    fields["experimental"] = true
  }
  if type_.deprecated {
    fields["deprecated"] = true
  }
  Json::object(fields)
}

///|
fn field_to_remote_json(field : ProtocolFieldSummary) -> Json {
  let fields : Map[String, Json] = { "name": field.name }
  apply_remote_kind(fields, field.kind)
  if field.optional {
    fields["optional"] = true
  }
  if field.experimental {
    fields["experimental"] = true
  }
  if field.deprecated {
    fields["deprecated"] = true
  }
  Json::object(fields)
}

///|
fn apply_remote_kind(fields : Map[String, Json], kind : String) -> Unit {
  match kind.strip_prefix("array<") {
    Some(rest) =>
      match rest.strip_suffix(">") {
        Some(item_kind) => {
          fields["type"] = "array"
          let item_fields : Map[String, Json] = {}
          apply_remote_kind(item_fields, item_kind.to_owned())
          fields["items"] = Json::object(item_fields)
        }
        None => fields["type"] = Json::string(kind)
      }
    None =>
      match kind {
        "any" => ()
        "string"
        | "binary"
        | "integer"
        | "number"
        | "boolean"
        | "object"
        | "array" => fields["type"] = Json::string(kind)
        ref_ => fields["$ref"] = Json::string(ref_)
      }
  }
}
