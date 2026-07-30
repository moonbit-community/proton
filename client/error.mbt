///|
/// Failures raised by the typed frontend client.
pub(all) suberror ClientFailure {
  BridgeUnavailable
  RequestCancelled
  RequestTimedOut
  InvalidContract(message~ : String)
  RemoteFailure(code~ : String, message~ : String, detail~ : String?)
  TransportFailure(message~ : String)
  ResponseDecode(message~ : String)
  EventDecode(message~ : String)
} derive(Debug, Eq)

///|
/// Returns a user-facing description of this client failure.
pub fn ClientFailure::message(self : ClientFailure) -> String {
  match self {
    BridgeUnavailable => "the Proton bridge is not available on this page"
    RequestCancelled => "the Proton bridge request was cancelled"
    RequestTimedOut => "the Proton bridge request timed out"
    InvalidContract(message~) => "invalid Proton contract: " + message
    RemoteFailure(code~, message~, detail~) =>
      match detail {
        Some(detail) =>
          "remote command failed [" +
          code +
          "]: " +
          message +
          " (" +
          detail +
          ")"
        None => "remote command failed [" + code + "]: " + message
      }
    TransportFailure(message~) => "Proton bridge transport failed: " + message
    ResponseDecode(message~) =>
      "failed to decode the Proton command response: " + message
    EventDecode(message~) =>
      "failed to decode the Proton event payload: " + message
  }
}

///|
impl Show for ClientFailure with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
priv struct BridgeFailureWire {
  code : String
  message : String
  detail : String?
} derive(FromJson)

///|
fn decode_bridge_failure(raw : String) -> ClientFailure {
  let wire : BridgeFailureWire = @json.from_json(@json.parse(raw)) catch {
    _ => return TransportFailure(message=raw)
  }
  match wire.code {
    "bridge_unavailable" => BridgeUnavailable
    "request_cancelled" => RequestCancelled
    "request_timeout" => RequestTimedOut
    "transport_failure" => TransportFailure(message=wire.message)
    code => RemoteFailure(code~, message=wire.message, detail=wire.detail)
  }
}
