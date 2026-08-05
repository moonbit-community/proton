///|
/// Detailed coverage report for generated typed CDP helpers.
///
/// Missing counts compare the bundled protocol manifest with generated command
/// builders, event builders, parameter types, result decoders, and domain type
/// declarations.
///
/// # Example
/// ```mbt nocheck
/// let report = protocol_typed_coverage_report()
/// assert_true(report.complete)
/// ```
pub(all) struct ProtocolTypedCoverageReport {
  domain_count : Int
  source_count : Int
  command_count : Int
  command_registry_count : Int
  command_registry_missing_count : Int
  event_count : Int
  event_registry_count : Int
  event_registry_missing_count : Int
  type_count : Int
  type_registry_count : Int
  type_registry_missing_count : Int
  command_with_params_count : Int
  typed_command_params_count : Int
  typed_command_params_missing_count : Int
  command_with_returns_count : Int
  typed_command_result_count : Int
  typed_command_result_missing_count : Int
  typed_command_result_decoder_count : Int
  typed_command_result_decoder_missing_count : Int
  event_with_params_count : Int
  typed_event_params_count : Int
  typed_event_params_missing_count : Int
  typed_event_decoder_count : Int
  typed_event_decoder_missing_count : Int
  typed_command_builder_count : Int
  typed_command_builder_missing_count : Int
  typed_event_builder_count : Int
  typed_event_builder_missing_count : Int
  typed_domain_type_count : Int
  typed_domain_type_missing_count : Int
  complete : Bool
} derive(Eq, ToJson, Debug)

///|
/// Return detailed generated typed protocol coverage counters.
///
/// `complete` is true only when every bundled command, event, type, and typed
/// helper category has zero missing entries.
///
/// # Example
/// ```mbt nocheck
/// let report = protocol_typed_coverage_report()
/// inspect(report.typed_command_builder_missing_count, content="0")
/// ```
pub fn protocol_typed_coverage_report() -> ProtocolTypedCoverageReport {
  let manifest = @protocol.protocol_manifest()
  let command_count = manifest.command_count()
  let event_count = manifest.event_count()
  let type_count = manifest.type_count()
  let command_registry_count = @protocol.protocol_commands().length()
  let event_registry_count = @protocol.protocol_events().length()
  let type_registry_count = @protocol.protocol_types().length()
  let command_with_params_count = @protocol.protocol_commands()
    .filter(command => command.parameter_count > 0)
    .length()
  let command_with_returns_count = @protocol.protocol_commands()
    .filter(command => command.return_count > 0)
    .length()
  let event_with_params_count = @protocol.protocol_events()
    .filter(event => event.parameter_count > 0)
    .length()
  let typed_command_builder_count = protocol_typed_command_builder_count()
  let typed_command_params_count = protocol_typed_command_params_count()
  let typed_command_result_count = protocol_typed_command_result_count()
  let typed_command_result_decoder_count = protocol_typed_command_result_decoder_count()
  let typed_event_builder_count = protocol_typed_event_builder_count()
  let typed_event_params_count = protocol_typed_event_params_count()
  let typed_event_decoder_count = protocol_typed_event_decoder_count()
  let typed_domain_type_count = protocol_typed_domain_type_count()
  let command_registry_missing_count = missing_count(
    command_count, command_registry_count,
  )
  let event_registry_missing_count = missing_count(
    event_count, event_registry_count,
  )
  let type_registry_missing_count = missing_count(
    type_count, type_registry_count,
  )
  let typed_command_builder_missing_count = missing_count(
    command_count, typed_command_builder_count,
  )
  let typed_command_params_missing_count = missing_count(
    command_with_params_count, typed_command_params_count,
  )
  let typed_command_result_missing_count = missing_count(
    command_with_returns_count, typed_command_result_count,
  )
  let typed_command_result_decoder_missing_count = missing_count(
    command_with_returns_count, typed_command_result_decoder_count,
  )
  let typed_event_builder_missing_count = missing_count(
    event_count, typed_event_builder_count,
  )
  let typed_event_params_missing_count = missing_count(
    event_with_params_count, typed_event_params_count,
  )
  let typed_event_decoder_missing_count = missing_count(
    event_with_params_count, typed_event_decoder_count,
  )
  let typed_domain_type_missing_count = missing_count(
    type_count, typed_domain_type_count,
  )
  {
    domain_count: manifest.domain_count(),
    source_count: manifest.sources.length(),
    command_count,
    command_registry_count,
    command_registry_missing_count,
    event_count,
    event_registry_count,
    event_registry_missing_count,
    type_count,
    type_registry_count,
    type_registry_missing_count,
    command_with_params_count,
    typed_command_params_count,
    typed_command_params_missing_count,
    command_with_returns_count,
    typed_command_result_count,
    typed_command_result_missing_count,
    typed_command_result_decoder_count,
    typed_command_result_decoder_missing_count,
    event_with_params_count,
    typed_event_params_count,
    typed_event_params_missing_count,
    typed_event_decoder_count,
    typed_event_decoder_missing_count,
    typed_command_builder_count,
    typed_command_builder_missing_count,
    typed_event_builder_count,
    typed_event_builder_missing_count,
    typed_domain_type_count,
    typed_domain_type_missing_count,
    complete: command_registry_missing_count == 0 &&
    event_registry_missing_count == 0 &&
    type_registry_missing_count == 0 &&
    typed_command_builder_missing_count == 0 &&
    typed_command_params_missing_count == 0 &&
    typed_command_result_missing_count == 0 &&
    typed_command_result_decoder_missing_count == 0 &&
    typed_event_builder_missing_count == 0 &&
    typed_event_params_missing_count == 0 &&
    typed_event_decoder_missing_count == 0 &&
    typed_domain_type_missing_count == 0,
  }
}

///|
// Return how many expected entries are missing, clamped at zero.
fn missing_count(expected : Int, actual : Int) -> Int {
  if actual >= expected {
    0
  } else {
    expected - actual
  }
}
