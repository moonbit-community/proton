///|
/// A client boundary independent of the active renderer. Implementations receive
/// JSON text and must return idempotent cancellation/unsubscription functions.
/// Cancelling stops observation; it does not roll back backend side effects.
pub struct Client {
  start_request : (String, String, (String) -> Unit, (ClientFailure) -> Unit) -> () -> Unit
  start_listener : (String, (String) -> Unit) -> (() -> Unit) raise ClientFailure
}

///|
/// Creates an isolated client, for example for browser previews and tests.
pub fn Client::Client(
  invoke~ : (String, String, (String) -> Unit, (ClientFailure) -> Unit) -> () -> Unit,
  subscribe~ : (String, (String) -> Unit) -> (() -> Unit) raise ClientFailure,
) -> Client {
  { start_request: invoke, start_listener: subscribe, }
}

///|
/// The default client resolves Proton's bridge when an operation starts.
pub let desktop : Client = Client(
  invoke=fn(route, request, success, failure) {
    let controller = @js_async.AbortController::new()
    invoke_json_with_callbacks(route, request, controller.signal(), success, raw => {
      failure(decode_bridge_failure(raw))
    })
    () => controller.abort()
  },
  subscribe=fn(route, received) raise ClientFailure {
    guard bridge_available() else { raise BridgeUnavailable }
    subscribe_json(route, received)
  },
)
