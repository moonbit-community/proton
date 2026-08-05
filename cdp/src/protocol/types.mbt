///|
/// CDP protocol version from the bundled schema manifest.
///
/// CDP version components are strings because Chrome's protocol JSON models
/// them as strings. Do not parse them as semantic versions; compare the fields
/// only when a caller explicitly needs an exact bundled-vs-remote check.
pub(all) struct ProtocolVersion {
  major : String
  minor : String
} derive(Eq, ToJson, Debug)

///|
/// Per-domain counts and flags from the bundled protocol schema.
///
/// `protocol` identifies the source schema bucket, for example browser or
/// JavaScript protocol data. `domain` is the CDP domain name such as `Page`.
/// Counts reflect modeled commands, events, and domain types after generation.
pub(all) struct ProtocolDomainSummary {
  protocol : String
  domain : String
  command_count : Int
  event_count : Int
  type_count : Int
  experimental : Bool
  deprecated : Bool
} derive(Eq, ToJson, Debug)

///|
/// Metadata about one source schema file used to generate the bundled manifest.
///
/// `sha256` and `byte_count` let tests and release tooling verify that the
/// bundled manifest was generated from the expected protocol JSON inputs.
pub(all) struct ProtocolSchemaSource {
  protocol : String
  path : String
  sha256 : String
  byte_count : Int
  domain_count : Int
  command_count : Int
  event_count : Int
  type_count : Int
} derive(Eq, ToJson, Debug)

///|
/// Compact summary of a command parameter, command return, event parameter, or
/// type property.
///
/// `kind` is the compact CDP type representation used by this library, such as
/// `string`, `integer`, `array<string>`, or a domain-local `$ref`. The boolean
/// flags include field-level flags plus any inherited domain/command/type flags
/// already applied by the generator.
pub(all) struct ProtocolFieldSummary {
  name : String
  kind : String
  optional : Bool
  experimental : Bool
  deprecated : Bool
} derive(Eq, ToJson, Debug)

///|
/// Bundled metadata for one CDP command.
///
/// `cdp_method` is the fully qualified method name sent over the wire, for
/// example `Page.navigate`. Parameter and return arrays store compact
/// `name[:type]` strings, with `?` after the name for optional fields.
///
/// `parameter_details` and `return_details` carry the same fields in a
/// structured form for callers that need optional/experimental/deprecated flags
/// without parsing the compact strings.
pub(all) struct ProtocolCommand {
  protocol : String
  domain : String
  name : String
  cdp_method : String
  parameter_count : Int
  return_count : Int
  parameters : Array[String]
  returns : Array[String]
  parameter_details : Array[ProtocolFieldSummary]
  return_details : Array[ProtocolFieldSummary]
  experimental : Bool
  deprecated : Bool
} derive(Eq, ToJson, Debug)

///|
/// Bundled metadata for one CDP event.
///
/// `cdp_method` is the event name received over the wire, for example
/// `Runtime.consoleAPICalled`. `parameters` uses the same compact format as
/// command parameters.
pub(all) struct ProtocolEvent {
  protocol : String
  domain : String
  name : String
  cdp_method : String
  parameter_count : Int
  parameters : Array[String]
  parameter_details : Array[ProtocolFieldSummary]
  experimental : Bool
  deprecated : Bool
} derive(Eq, ToJson, Debug)

///|
/// Bundled metadata for one CDP domain type.
///
/// `kind` is the declared CDP type kind. Object-like types expose
/// `properties` and `property_details`; enum-like types expose `enum_values`.
/// Some protocol types have both properties and enum values depending on the
/// upstream schema shape.
pub(all) struct ProtocolType {
  protocol : String
  domain : String
  name : String
  kind : String
  property_count : Int
  enum_count : Int
  properties : Array[String]
  property_details : Array[ProtocolFieldSummary]
  enum_values : Array[String]
  experimental : Bool
  deprecated : Bool
} derive(Eq, ToJson, Debug)

///|
/// Top-level manifest for the bundled CDP protocol schema.
///
/// Use `protocol_manifest` from the generated manifest file to obtain the
/// current value, then the count and lookup methods in this file to inspect it.
/// The manifest intentionally stores summary metadata; full generated typed
/// structs and builders live in `justjavac/cdp/protocol/typed`.
pub(all) struct ProtocolManifest {
  version : ProtocolVersion
  sources : Array[ProtocolSchemaSource]
  domains : Array[ProtocolDomainSummary]
} derive(Eq, ToJson, Debug)

///|
/// Return the number of protocol domains in the manifest.
pub fn ProtocolManifest::domain_count(self : ProtocolManifest) -> Int {
  self.domains.length()
}

///|
/// Return the total number of commands across all domains.
pub fn ProtocolManifest::command_count(self : ProtocolManifest) -> Int {
  self.domains.fold(init=0, (sum, item) => sum + item.command_count)
}

///|
/// Return the total number of events across all domains.
pub fn ProtocolManifest::event_count(self : ProtocolManifest) -> Int {
  self.domains.fold(init=0, (sum, item) => sum + item.event_count)
}

///|
/// Return the total number of domain types across all domains.
pub fn ProtocolManifest::type_count(self : ProtocolManifest) -> Int {
  self.domains.fold(init=0, (sum, item) => sum + item.type_count)
}

///|
/// Find a domain summary by exact domain name.
///
/// # Example
/// ```mbt nocheck
/// let page = protocol_manifest().find_domain("Page")
/// assert_true(page is Some(_))
/// ```
pub fn ProtocolManifest::find_domain(
  self : ProtocolManifest,
  domain : String,
) -> ProtocolDomainSummary? {
  for item in self.domains {
    if item.domain == domain {
      return Some(item)
    }
  }
  None
}

///|
/// Return all bundled commands in a domain.
///
/// `domain` is matched exactly and case-sensitively against names such as
/// `Browser`, `Target`, or `Runtime`.
pub fn protocol_commands_for_domain(domain : String) -> Array[ProtocolCommand] {
  protocol_commands().filter(item => item.domain == domain)
}

///|
/// Find a bundled command by exact CDP method name.
///
/// # Example
/// ```mbt nocheck
/// let command = protocol_command("Browser.getVersion")
/// assert_true(command is Some(_))
/// ```
pub fn protocol_command(method_name : String) -> ProtocolCommand? {
  for command in protocol_commands() {
    if command.cdp_method == method_name {
      return Some(command)
    }
  }
  None
}

///|
/// Search bundled commands by method, protocol, domain, name, parameter, or
/// return text.
///
/// The search is case-insensitive and ignores empty queries by returning an
/// empty result set.
pub fn protocol_commands_matching(query : String) -> Array[ProtocolCommand] {
  let needle = query.to_lower()
  protocol_commands().filter(command => command.matches_query(needle))
}

///|
/// Return all bundled events in a domain.
///
/// `domain` is matched exactly and case-sensitively.
pub fn protocol_events_for_domain(domain : String) -> Array[ProtocolEvent] {
  protocol_events().filter(item => item.domain == domain)
}

///|
/// Find a bundled event by exact CDP event method name.
///
/// Example event names include `Page.loadEventFired` and
/// `Runtime.consoleAPICalled`.
pub fn protocol_event(method_name : String) -> ProtocolEvent? {
  for event in protocol_events() {
    if event.cdp_method == method_name {
      return Some(event)
    }
  }
  None
}

///|
/// Search bundled events by method, protocol, domain, name, or parameter text.
///
/// The search is case-insensitive and returns an empty array for an empty query.
pub fn protocol_events_matching(query : String) -> Array[ProtocolEvent] {
  let needle = query.to_lower()
  protocol_events().filter(event => event.matches_query(needle))
}

///|
/// Return all bundled types in a domain.
///
/// `domain` is matched exactly and case-sensitively.
pub fn protocol_types_for_domain(domain : String) -> Array[ProtocolType] {
  protocol_types().filter(item => item.domain == domain)
}

///|
/// Find a bundled type by exact `Domain.TypeName`.
///
/// The lookup expects the fully qualified type name, even for types referenced
/// domain-locally in the upstream schema.
pub fn protocol_type(type_name : String) -> ProtocolType? {
  for type_ in protocol_types() {
    let full_name = "\{type_.domain}.\{type_.name}"
    if full_name == type_name {
      return Some(type_)
    }
  }
  None
}

///|
/// Search bundled types by full name, protocol, kind, property, or enum text.
///
/// The search is case-insensitive and returns an empty array for an empty query.
pub fn protocol_types_matching(query : String) -> Array[ProtocolType] {
  let needle = query.to_lower()
  protocol_types().filter(type_ => type_.matches_query(needle))
}

///|
// Return true when a command contains the normalized search text.
fn ProtocolCommand::matches_query(
  self : ProtocolCommand,
  needle : String,
) -> Bool {
  contains_protocol_query(self.cdp_method, needle) ||
  contains_protocol_query(self.protocol, needle) ||
  contains_protocol_query(self.domain, needle) ||
  contains_protocol_query(self.name, needle) ||
  protocol_items_match(self.parameters, needle) ||
  protocol_items_match(self.returns, needle)
}

///|
// Return true when an event contains the normalized search text.
fn ProtocolEvent::matches_query(self : ProtocolEvent, needle : String) -> Bool {
  contains_protocol_query(self.cdp_method, needle) ||
  contains_protocol_query(self.protocol, needle) ||
  contains_protocol_query(self.domain, needle) ||
  contains_protocol_query(self.name, needle) ||
  protocol_items_match(self.parameters, needle)
}

///|
// Return true when a type contains the normalized search text.
fn ProtocolType::matches_query(self : ProtocolType, needle : String) -> Bool {
  contains_protocol_query("\{self.domain}.\{self.name}", needle) ||
  contains_protocol_query(self.protocol, needle) ||
  contains_protocol_query(self.kind, needle) ||
  protocol_items_match(self.properties, needle) ||
  protocol_items_match(self.enum_values, needle)
}

///|
// Return true when any compact protocol item contains the search text.
fn protocol_items_match(items : Array[String], needle : String) -> Bool {
  for item in items {
    if contains_protocol_query(item, needle) {
      return true
    }
  }
  false
}

///|
// Perform a case-insensitive non-empty substring query.
fn contains_protocol_query(value : String, needle : String) -> Bool {
  needle != "" && value.to_lower().contains(needle)
}
