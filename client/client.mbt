///|
/// Invokes a typed command through the bridge installed on the active page.
pub async fn[Request : ToJson, Response : @json.FromJson] invoke(
  command : @proton_contract.Command[Request, Response],
  request : Request,
) -> Response raise ClientFailure {
  command.validate() catch {
    error => raise InvalidContract(message=error.message())
  }
  guard bridge_available() else { raise BridgeUnavailable }
  let request_json = ToJson::to_json(request).stringify()
  let response_json = @js_async.run_promise(signal => {
    invoke_json(command.contract_route().operation_name(), request_json, signal)
  }) catch {
    error => raise decode_bridge_failure(error.to_string())
  }
  @json.from_json(@json.parse(response_json)) catch {
    error => raise ResponseDecode(message=error.to_string())
  }
}

///|
/// Invokes a typed command without entering the MoonBit async scheduler.
///
/// Framework adapters use this callback boundary when their effect runtime
/// owns scheduling. Application code should use `invoke`.
/// The returned function idempotently cancels the request if it is still active.
#doc(hidden)
pub fn[Request : ToJson, Response : @json.FromJson] invoke_with_callbacks(
  command : @proton_contract.Command[Request, Response],
  request : Request,
  success : (Response) -> Unit,
  failure : (ClientFailure) -> Unit,
) -> () -> Unit {
  command.validate() catch {
    error => {
      failure(InvalidContract(message=error.message()))
      return () => ()
    }
  }
  let request_json = ToJson::to_json(request).stringify()
  let controller = @js_async.AbortController::new()
  invoke_json_with_callbacks(
    command.contract_route().operation_name(),
    request_json,
    controller.signal(),
    response_json => {
      let response : Response = @json.from_json(@json.parse(response_json)) catch {
        error => {
          failure(ResponseDecode(message=error.to_string()))
          return
        }
      }
      success(response)
    },
    raw => failure(decode_bridge_failure(raw)),
  )
  () => controller.abort()
}

///|
/// A live event subscription installed on the active renderer page.
pub struct Subscription {
  mut closed : Bool
  close_listener : () -> Unit
}

///|
/// Removes this subscription. Repeated calls have no effect.
pub fn Subscription::close(self : Subscription) -> Unit {
  if !self.closed {
    self.closed = true
    (self.close_listener)()
  }
}

///|
/// Subscribes to a typed live event on the active renderer page.
///
/// A malformed payload reports `EventDecode` through `failure` without
/// removing the subscription.
pub fn[Payload : @json.FromJson] subscribe(
  event : @proton_contract.Event[Payload],
  received : (Payload) -> Unit,
  failure : (ClientFailure) -> Unit,
) -> Subscription raise ClientFailure {
  event.validate() catch {
    error => raise InvalidContract(message=error.message())
  }
  guard bridge_available() else { raise BridgeUnavailable }
  let close_listener = subscribe_json(event.contract_route().operation_name(), payload_json => {
    try {
      let payload : Payload = @json.from_json(@json.parse(payload_json))
      received(payload)
    } catch {
      error => failure(EventDecode(message=error.to_string()))
    }
  })
  Subscription::{ closed: false, close_listener }
}
