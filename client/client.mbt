///|
/// Invokes a typed command through the bridge installed on the active page.
pub async fn[Request : ToJson, Response : @json.FromJson] invoke(
  command : @proton_contract.Command[Request, Response],
  request : Request,
) -> Response raise ClientFailure {
  desktop.invoke(command, request)
}

///|
/// Invokes a typed command using this client's boundary. Task cancellation
/// cancels the pending transport request.
pub async fn[Request : ToJson, Response : @json.FromJson] Client::invoke(
  self : Client,
  command : @proton_contract.Command[Request, Response],
  request : Request,
) -> Response raise ClientFailure {
  let outcome : Ref[Result[Response, ClientFailure]?] = Ref(None)
  let ready = @async.CondVar::Cond()
  let cancel = self.invoke_with_callbacks(
    command,
    request,
    value => {
      outcome.val = Some(Ok(value))
      ready.signal()
    },
    error => {
      outcome.val = Some(Err(error))
      ready.signal()
    },
  )
  defer cancel()
  while outcome.val is None {
    ready.wait() catch {
      _ => raise RequestCancelled
    }
  }
  match outcome.val {
    Some(Ok(value)) => value
    Some(Err(error)) => raise error
    None => abort("request completed without a result")
  }
}

///|
/// Starts a typed request on the desktop client. The returned function cancels
/// observation and requests transport cancellation exactly once.
pub fn[Request : ToJson, Response : @json.FromJson] invoke_with_callbacks(
  command : @proton_contract.Command[Request, Response],
  request : Request,
  success : (Response) -> Unit,
  failure : (ClientFailure) -> Unit,
) -> () -> Unit {
  desktop.invoke_with_callbacks(command, request, success, failure)
}

///|
/// Starts a typed request without entering an async scheduler. Late responses
/// after cancellation and repeated completions are ignored.
pub fn[Request : ToJson, Response : @json.FromJson] Client::invoke_with_callbacks(
  self : Client,
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
  let active = Ref(true)
  let cancel = (self.start_request)(
    command.contract_route().operation_name(),
    ToJson::to_json(request).stringify(),
    response_json => {
      guard active.val else { return }
      active.val = false
      let response : Response = @json.from_json(@json.parse(response_json)) catch {
        error => {
          failure(ResponseDecode(message=error.to_string()))
          return
        }
      }
      success(response)
    },
    error => {
      guard active.val else { return }
      active.val = false
      failure(error)
    },
  )
  () => {
    if active.val {
      active.val = false
      cancel()
    }
  }
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
  desktop.subscribe(event, received, failure)
}

///|
/// Installs an independent listener. Closing it also suppresses queued events.
pub fn[Payload : @json.FromJson] Client::subscribe(
  self : Client,
  event : @proton_contract.Event[Payload],
  received : (Payload) -> Unit,
  failure : (ClientFailure) -> Unit,
) -> Subscription raise ClientFailure {
  event.validate() catch {
    error => raise InvalidContract(message=error.message())
  }
  self.listen_json(event.contract_route().operation_name(), payload_json => {
    let payload : Payload = @json.from_json(@json.parse(payload_json)) catch {
      error => {
        failure(EventDecode(message=error.to_string()))
        return
      }
    }
    received(payload)
  })
}

///|
/// Framework integration boundary. Prefer typed subscriptions in application code.
#doc(hidden)
pub fn Client::listen_json(
  self : Client,
  route : String,
  received : (String) -> Unit,
) -> Subscription raise ClientFailure {
  let active = Ref(true)
  let close_listener = (self.start_listener)(route, value => {
    if active.val {
      received(value)
    }
  })
  Subscription::{
    closed: false,
    close_listener: () => {
      active.val = false
      close_listener()
    },
  }
}
