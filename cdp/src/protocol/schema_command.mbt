///|
/// Errors raised by schema-aware CDP command, response, and event validation.
///
/// The first string in each command/event/result variant is the full CDP method
/// name, such as `Runtime.evaluate`. Field variants use the second string for
/// the parameter or return field name. Type mismatch variants include the
/// expected compact protocol kind used by the bundled manifest.
pub(all) suberror ProtocolSchemaError {
  UnknownCommand(String)
  UnsupportedRemoteCommand(String)
  UnknownEvent(String)
  ExpectedParamsObject(String)
  MissingParameter(String, String)
  UnknownParameter(String, String)
  InvalidParameterType(String, String, String)
  ExpectedResultObject(String)
  MissingReturn(String, String)
  UnknownReturn(String, String)
  InvalidReturnType(String, String, String)
} derive(Eq, ToJson, Debug)

///|
/// Stable diagnostic data for a `ProtocolSchemaError`.
///
/// This struct is useful for CLI output, logs, and tests that should not match
/// against formatted human text. `path` points at the command, event, params
/// field, or result field that failed validation.
pub(all) struct ProtocolSchemaErrorDiagnostic {
  kind : String
  method_name : String?
  field_name : String?
  path : String
  expected_type : String?
} derive(Eq, ToJson, Debug)

///|
/// Convert a schema error into structured diagnostic data.
///
/// # Example
/// ```mbt nocheck
/// let diagnostic = ProtocolSchemaError::UnknownCommand("Nope.run").diagnostic()
/// assert_eq(diagnostic.kind, "unknown_command")
/// ```
pub fn ProtocolSchemaError::diagnostic(
  self : ProtocolSchemaError,
) -> ProtocolSchemaErrorDiagnostic {
  {
    kind: self.kind(),
    method_name: self.method_name(),
    field_name: self.field_name(),
    path: self.path(),
    expected_type: self.expected_type(),
  }
}

///|
/// Return the stable machine-readable error kind.
pub fn ProtocolSchemaError::kind(self : ProtocolSchemaError) -> String {
  match self {
    UnknownCommand(_) => "unknown_command"
    UnsupportedRemoteCommand(_) => "unsupported_remote_command"
    UnknownEvent(_) => "unknown_event"
    ExpectedParamsObject(_) => "expected_params_object"
    MissingParameter(_, _) => "missing_parameter"
    UnknownParameter(_, _) => "unknown_parameter"
    InvalidParameterType(_, _, _) => "invalid_parameter_type"
    ExpectedResultObject(_) => "expected_result_object"
    MissingReturn(_, _) => "missing_return"
    UnknownReturn(_, _) => "unknown_return"
    InvalidReturnType(_, _, _) => "invalid_return_type"
  }
}

///|
/// Return the CDP method name associated with this schema error.
pub fn ProtocolSchemaError::method_name(self : ProtocolSchemaError) -> String? {
  match self {
    UnknownCommand(method_name)
    | UnsupportedRemoteCommand(method_name)
    | UnknownEvent(method_name)
    | ExpectedParamsObject(method_name)
    | MissingParameter(method_name, _)
    | UnknownParameter(method_name, _)
    | InvalidParameterType(method_name, _, _)
    | ExpectedResultObject(method_name)
    | MissingReturn(method_name, _)
    | UnknownReturn(method_name, _)
    | InvalidReturnType(method_name, _, _) => Some(method_name)
  }
}

///|
/// Return the parameter or return field name associated with this error.
pub fn ProtocolSchemaError::field_name(self : ProtocolSchemaError) -> String? {
  match self {
    MissingParameter(_, field_name)
    | UnknownParameter(_, field_name)
    | InvalidParameterType(_, field_name, _)
    | MissingReturn(_, field_name)
    | UnknownReturn(_, field_name)
    | InvalidReturnType(_, field_name, _) => Some(field_name)
    UnknownCommand(_)
    | UnsupportedRemoteCommand(_)
    | UnknownEvent(_)
    | ExpectedParamsObject(_)
    | ExpectedResultObject(_) => None
  }
}

///|
/// Return a JSON-style validation path for this schema error.
pub fn ProtocolSchemaError::path(self : ProtocolSchemaError) -> String {
  match self {
    UnknownCommand(method_name)
    | UnsupportedRemoteCommand(method_name)
    | UnknownEvent(method_name) => method_name
    ExpectedParamsObject(method_name) => "\{method_name}.params"
    MissingParameter(method_name, field_name)
    | UnknownParameter(method_name, field_name)
    | InvalidParameterType(method_name, field_name, _) =>
      "\{method_name}.params.\{field_name}"
    ExpectedResultObject(method_name) => "\{method_name}.result"
    MissingReturn(method_name, field_name)
    | UnknownReturn(method_name, field_name)
    | InvalidReturnType(method_name, field_name, _) =>
      "\{method_name}.result.\{field_name}"
  }
}

///|
/// Return the expected protocol type for type mismatch errors.
pub fn ProtocolSchemaError::expected_type(
  self : ProtocolSchemaError,
) -> String? {
  match self {
    InvalidParameterType(_, _, expected) | InvalidReturnType(_, _, expected) =>
      Some(expected)
    UnknownCommand(_)
    | UnsupportedRemoteCommand(_)
    | UnknownEvent(_)
    | ExpectedParamsObject(_)
    | MissingParameter(_, _)
    | UnknownParameter(_, _)
    | ExpectedResultObject(_)
    | MissingReturn(_, _)
    | UnknownReturn(_, _) => None
  }
}

///|
/// Compact coverage status for bundled protocol registries.
///
/// `*_count` fields are derived from the manifest domain summaries.
/// `*_registry_count` fields are derived from generated lookup registries.
/// `complete` is true when every manifest command, event, and type has a
/// registry entry.
pub(all) struct ProtocolCoverage {
  domain_count : Int
  command_count : Int
  event_count : Int
  type_count : Int
  command_registry_count : Int
  event_registry_count : Int
  type_registry_count : Int
  complete : Bool
} derive(Eq, ToJson, Debug)

///|
/// Return a compact completeness check for command, event, and type registries.
///
/// This is intended for generator tests and release checks. It does not measure
/// generated typed builder coverage; use `protocol_typed_coverage_report` from
/// `protocol/typed` for that wider check.
pub fn protocol_coverage() -> ProtocolCoverage {
  let manifest = protocol_manifest()
  let command_count = manifest.command_count()
  let event_count = manifest.event_count()
  let type_count = manifest.type_count()
  let command_registry_count = protocol_commands().length()
  let event_registry_count = protocol_events().length()
  let type_registry_count = protocol_types().length()
  {
    domain_count: manifest.domain_count(),
    command_count,
    event_count,
    type_count,
    command_registry_count,
    event_registry_count,
    type_registry_count,
    complete: command_count == command_registry_count &&
    event_count == event_registry_count &&
    type_count == type_registry_count,
  }
}

///|
/// Build a CDP command after validating method existence and parameter shape.
///
/// This function uses the bundled protocol schema only. To additionally verify
/// that a live browser advertises the command, use `cdp_remote_schema_command`.
///
/// # Example
/// ```mbt nocheck
/// let command = cdp_schema_command(id=1, method_name="Browser.getVersion")
/// assert_eq(command.method_name, "Browser.getVersion")
/// ```
pub fn cdp_schema_command(
  id~ : Int,
  method_name~ : String,
  params? : Json,
  session_id? : String,
) -> CdpCommandMessage raise ProtocolSchemaError {
  match protocol_command(method_name) {
    Some(command) => command.build_command(id~, params?, session_id?)
    None => raise UnknownCommand(method_name)
  }
}

///|
/// Build a schema-validated command and require it to exist in a remote schema.
///
/// Pass the JSON returned by Chrome's `/json/protocol` as `remote_schema`. This
/// is useful for end-to-end tests against browsers whose protocol version may
/// differ from the bundled schema.
pub fn cdp_remote_schema_command(
  id~ : Int,
  method_name~ : String,
  remote_schema~ : Json,
  params? : Json,
  session_id? : String,
) -> CdpCommandMessage raise ProtocolSchemaError {
  let command = cdp_schema_command(id~, method_name~, params?, session_id?)
  if protocol_remote_has_command(remote_schema, method_name) {
    command
  } else {
    raise UnsupportedRemoteCommand(method_name)
  }
}

///|
/// Return true when a `/json/protocol` schema advertises a CDP command.
pub fn protocol_remote_has_command(
  remote_schema : Json,
  method_name : String,
) -> Bool {
  let (domain_name, command_name) = split_cdp_method(method_name)
  match remote_schema {
    Object(schema_fields) =>
      match schema_fields.get("domains") {
        Some(Array(domains)) =>
          domains.any(domain => {
            match domain {
              Object(domain_fields) =>
                match domain_fields.get("domain") {
                  Some(String(name)) if name == domain_name =>
                    remote_domain_has_command(domain_fields, command_name)
                  _ => false
                }
              _ => false
            }
          })
        _ => false
      }
    _ => false
  }
}

///|
/// Build a CDP event after validating method existence and parameter shape.
///
/// This is primarily useful for tests and for code that wants to synthesize
/// event envelopes with the same validation rules used for incoming event
/// metadata. Real browser events are parsed with `parse_cdp_incoming`.
pub fn cdp_schema_event(
  method_name~ : String,
  params? : Json,
  session_id? : String,
) -> CdpEventMessage raise ProtocolSchemaError {
  match protocol_event(method_name) {
    Some(event) => event.build_event(params?, session_id?)
    None => raise UnknownEvent(method_name)
  }
}

///|
// Return true when a remote domain JSON object contains a command name.
fn remote_domain_has_command(
  domain_fields : Map[String, Json],
  command_name : String,
) -> Bool {
  match domain_fields.get("commands") {
    Some(Array(commands)) =>
      commands.any(command => {
        match command {
          Object(command_fields) =>
            match command_fields.get("name") {
              Some(String(name)) => name == command_name
              _ => false
            }
          _ => false
        }
      })
    _ => false
  }
}

///|
// Split `Domain.method` into domain and method components.
fn split_cdp_method(method_name : String) -> (String, String) {
  match method_name.find(".") {
    Some(index) =>
      (method_name[:index].to_owned(), method_name[index + 1:].to_owned())
    None => ("", method_name)
  }
}

///|
/// Build a command from this manifest entry after validating parameters.
///
/// Call this method when you already resolved a `ProtocolCommand` and want to
/// avoid another registry lookup.
pub fn ProtocolCommand::build_command(
  self : ProtocolCommand,
  id~ : Int,
  params? : Json,
  session_id? : String,
) -> CdpCommandMessage raise ProtocolSchemaError {
  self.validate_params(params?)
  cdp_command(id~, method_name=self.cdp_method, params?, session_id?)
}

///|
/// Validate a CDP response against the bundled command return schema.
///
/// Error responses are returned unchanged because CDP errors are protocol-level
/// failures and do not have command-specific result fields.
pub fn cdp_schema_response(
  method_name~ : String,
  response : CdpResponseMessage,
) -> CdpResponseMessage raise ProtocolSchemaError {
  match protocol_command(method_name) {
    Some(command) => {
      command.validate_response(response)
      response
    }
    None => raise UnknownCommand(method_name)
  }
}

///|
/// Validate a response result against this command's return schema.
///
/// CDP error responses are intentionally accepted without result validation.
/// For successful responses, missing required return fields, unknown return
/// fields, and modeled primitive type mismatches raise `ProtocolSchemaError`.
pub fn ProtocolCommand::validate_response(
  self : ProtocolCommand,
  response : CdpResponseMessage,
) -> Unit raise ProtocolSchemaError {
  if response.error is Some(_) {
    return
  }
  validate_protocol_result(
    self.cdp_method,
    self.domain,
    self.returns,
    response.result,
  )
}

///|
/// Build an event from this manifest entry after validating parameters.
///
/// Call this method when you already resolved a `ProtocolEvent` and want to
/// avoid another registry lookup.
pub fn ProtocolEvent::build_event(
  self : ProtocolEvent,
  params? : Json,
  session_id? : String,
) -> CdpEventMessage raise ProtocolSchemaError {
  validate_protocol_params(
    self.cdp_method,
    self.domain,
    self.parameters,
    params?,
  )
  { method_name: self.cdp_method, params, session_id }
}

///|
/// Return required parameter names for this command.
///
/// Optional compact fields are encoded with a `?` suffix before the optional
/// `:type` portion and are excluded from this result.
pub fn ProtocolCommand::required_parameters(
  self : ProtocolCommand,
) -> Array[String] {
  self.parameters
  .filter(item => !protocol_item_optional(item))
  .map(protocol_item_name)
}

///|
/// Return required result field names for this command.
///
/// Commands with no required return fields return an empty array.
pub fn ProtocolCommand::required_returns(
  self : ProtocolCommand,
) -> Array[String] {
  self.returns
  .filter(item => !protocol_item_optional(item))
  .map(protocol_item_name)
}

///|
/// Return required parameter names for this event.
///
/// Events with no required parameters return an empty array.
pub fn ProtocolEvent::required_parameters(
  self : ProtocolEvent,
) -> Array[String] {
  self.parameters
  .filter(item => !protocol_item_optional(item))
  .map(protocol_item_name)
}

///|
/// Return all parameter names for this command.
///
/// Optionality and type suffixes are stripped from the compact manifest strings.
pub fn ProtocolCommand::parameter_names(
  self : ProtocolCommand,
) -> Array[String] {
  self.parameters.map(protocol_item_name)
}

///|
/// Return all result field names for this command.
///
/// Optionality and type suffixes are stripped from the compact manifest strings.
pub fn ProtocolCommand::return_names(self : ProtocolCommand) -> Array[String] {
  self.returns.map(protocol_item_name)
}

///|
/// Return all parameter names for this event.
///
/// Optionality and type suffixes are stripped from the compact manifest strings.
pub fn ProtocolEvent::parameter_names(self : ProtocolEvent) -> Array[String] {
  self.parameters.map(protocol_item_name)
}

///|
// Validate this command's parameter object.
fn ProtocolCommand::validate_params(
  self : ProtocolCommand,
  params? : Json,
) -> Unit raise ProtocolSchemaError {
  validate_protocol_params(
    self.cdp_method,
    self.domain,
    self.parameters,
    params?,
  )
}

///|
// Validate required, unknown, and typed parameter fields.
fn validate_protocol_params(
  method_name : String,
  domain : String,
  parameters : Array[String],
  params? : Json,
) -> Unit raise ProtocolSchemaError {
  let required = parameters
    .filter(item => !protocol_item_optional(item))
    .map(protocol_item_name)
  match params {
    Some(Object(fields)) => {
      for name in required {
        if fields.get(name) is None {
          raise MissingParameter(method_name, name)
        }
      }
      let allowed = parameters.map(protocol_item_name)
      for name, _ in fields {
        if !allowed.contains(name) {
          raise UnknownParameter(method_name, name)
        }
      }
      validate_protocol_param_types(method_name, domain, parameters, fields)
    }
    Some(_) => raise ExpectedParamsObject(method_name)
    None =>
      match required {
        [first, ..] => raise MissingParameter(method_name, first)
        [] => ()
      }
  }
}

///|
// Validate parameter JSON values against compact protocol types.
fn validate_protocol_param_types(
  method_name : String,
  domain : String,
  parameters : Array[String],
  fields : Map[String, Json],
) -> Unit raise ProtocolSchemaError {
  for item in parameters {
    let name = protocol_item_name(item)
    match fields.get(name) {
      Some(Null) if protocol_item_optional(item) => ()
      Some(value) => {
        let expected = protocol_item_type(item)
        if !json_matches_protocol_type(value, domain, expected) {
          raise InvalidParameterType(method_name, name, expected)
        }
      }
      None => ()
    }
  }
}

///|
// Validate required, unknown, and typed response result fields.
fn validate_protocol_result(
  method_name : String,
  domain : String,
  returns : Array[String],
  result : Json?,
) -> Unit raise ProtocolSchemaError {
  let required = returns
    .filter(item => !protocol_item_optional(item))
    .map(protocol_item_name)
  match result {
    Some(Object(fields)) => {
      for name in required {
        if fields.get(name) is None {
          raise MissingReturn(method_name, name)
        }
      }
      let allowed = returns.map(protocol_item_name)
      for name, _ in fields {
        if !allowed.contains(name) {
          raise UnknownReturn(method_name, name)
        }
      }
      validate_protocol_return_types(method_name, domain, returns, fields)
    }
    Some(_) => raise ExpectedResultObject(method_name)
    None =>
      match required {
        [first, ..] => raise MissingReturn(method_name, first)
        [] => ()
      }
  }
}

///|
// Validate result JSON values against compact protocol types.
fn validate_protocol_return_types(
  method_name : String,
  domain : String,
  returns : Array[String],
  fields : Map[String, Json],
) -> Unit raise ProtocolSchemaError {
  for item in returns {
    let name = protocol_item_name(item)
    match fields.get(name) {
      Some(Null) if protocol_item_optional(item) => ()
      Some(value) => {
        let expected = protocol_item_type(item)
        if !json_matches_protocol_type(value, domain, expected) {
          raise InvalidReturnType(method_name, name, expected)
        }
      }
      None => ()
    }
  }
}

///|
// Extract a field name from a compact `name?:type` item.
fn protocol_item_name(item : String) -> String {
  let head = item.split(":").to_array()[0].to_owned()
  if head.has_suffix("?") {
    head[:head.length() - 1].to_owned()
  } else {
    head
  }
}

///|
// Return true when a compact protocol item is optional.
fn protocol_item_optional(item : String) -> Bool {
  item.split(":").to_array()[0].has_suffix("?")
}

///|
// Extract a type name from a compact protocol item.
fn protocol_item_type(item : String) -> String {
  let parts = item.split(":").to_array()
  match parts {
    [_, type_name] => type_name.to_owned()
    _ => "any"
  }
}

///|
// Return true when a JSON value conforms to a compact protocol type.
fn json_matches_protocol_type(
  value : Json,
  domain : String,
  expected : String,
) -> Bool {
  if expected.has_prefix("array<") {
    return value is Array(_)
  }
  json_matches_protocol_kind(value, protocol_type_kind(domain, expected))
}

///|
// Return true when a JSON value conforms to a resolved protocol kind.
fn json_matches_protocol_kind(value : Json, kind : String) -> Bool {
  match kind {
    "any" => true
    "string" | "binary" => value is String(_)
    "integer" => json_is_integer(value)
    "number" => value is Number(_)
    "boolean" => value is True || value is False
    "object" => value is Object(_)
    "array" => value is Array(_)
    _ => true
  }
}

///|
// Resolve primitive and domain-local type names to a validation kind.
fn protocol_type_kind(domain : String, expected : String) -> String {
  match expected {
    "any" | "string" | "binary" | "integer" | "number" | "boolean" | "object" =>
      expected
    _ =>
      match resolve_protocol_type(domain, expected) {
        Some(type_) => type_.kind
        None => "any"
      }
  }
}

///|
// Resolve a protocol type by fully-qualified or domain-local name.
fn resolve_protocol_type(domain : String, expected : String) -> ProtocolType? {
  if expected.contains(".") {
    protocol_type(expected)
  } else {
    protocol_type("\{domain}.\{expected}")
  }
}

///|
// Return true when a JSON number has no fractional part.
fn json_is_integer(value : Json) -> Bool {
  match value {
    Number(number, ..) => number.to_int().to_double() == number
    _ => false
  }
}
