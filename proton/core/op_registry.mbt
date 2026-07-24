///|
priv struct OpRegistry {
  handlers : Map[String, (Json) -> Json raise OpDispatchError]
  async_handlers : Map[String, async (AppCommandRequestContext, Json) -> Json]
}

///|
/// Creates an empty op handler registry.
fn OpRegistry::new() -> OpRegistry {
  OpRegistry::{ handlers: Map([]), async_handlers: Map([]) }
}

///|
/// Registers a typed op handler that cannot fail explicitly.
fn[Payload : @json.FromJson, Reply : ToJson] OpRegistry::handle(
  self : OpRegistry,
  name : String,
  callback : (Payload) -> Reply raise,
) -> Unit raise OpRegistrationError {
  validate_op_name(name)
  guard self.handler_name_available(name) else { raise DuplicateName(name~) }
  self.handlers.set(name, fn(payload_json) raise OpDispatchError {
    let payload : Payload = @json.from_json(payload_json) catch {
      err => raise InvalidPayload(name~, detail=err.to_string())
    }
    try callback(payload) catch {
      err =>
        raise HandlerFailed(name~, detail=@debug.render(@debug.to_repr(err)))
    } noraise {
      reply => ToJson::to_json(reply)
    }
  })
}

///|
/// Registers a typed async op handler.
fn[Payload : @json.FromJson, Reply : ToJson] OpRegistry::handle_async(
  self : OpRegistry,
  name : String,
  callback : async (Payload) -> Reply,
) -> Unit raise OpRegistrationError {
  validate_op_name(name)
  guard self.handler_name_available(name) else { raise DuplicateName(name~) }
  self.async_handlers.set(name, async fn(_context, payload_json) {
    let payload : Payload = @json.from_json(payload_json) catch {
      err => raise InvalidPayload(name~, detail=err.to_string())
    }
    try callback(payload) catch {
      err =>
        raise HandlerFailed(name~, detail=@debug.render(@debug.to_repr(err)))
    } noraise {
      reply => ToJson::to_json(reply)
    }
  })
}

///|
/// Registers a typed async op handler that receives request-scoped context.
fn[Payload : @json.FromJson, Reply : ToJson] OpRegistry::handle_async_with_context(
  self : OpRegistry,
  name : String,
  callback : async (AppCommandRequestContext, Payload) -> Reply,
) -> Unit raise OpRegistrationError {
  validate_op_name(name)
  guard self.handler_name_available(name) else { raise DuplicateName(name~) }
  self.async_handlers.set(name, async fn(context, payload_json) {
    let payload : Payload = @json.from_json(payload_json) catch {
      err => raise InvalidPayload(name~, detail=err.to_string())
    }
    try callback(context, payload) catch {
      err =>
        raise HandlerFailed(name~, detail=@debug.render(@debug.to_repr(err)))
    } noraise {
      reply => ToJson::to_json(reply)
    }
  })
}

///|
/// Runs a previously registered async op handler on the current async loop.
async fn OpRegistry::call_async_direct(
  self : OpRegistry,
  name : String,
  payload : Json,
) -> Json {
  self.call_async_direct_with_context(
    AppCommandRequestContext::new(0L),
    name,
    payload,
  )
}

///|
/// Runs a previously registered async op handler with request-scoped context.
async fn OpRegistry::call_async_direct_with_context(
  self : OpRegistry,
  context : AppCommandRequestContext,
  name : String,
  payload : Json,
) -> Json {
  match self.async_handlers.get(name) {
    Some(handler) => handler(context, payload)
    None => self.call(name, payload)
  }
}

///|
/// Returns whether an op name has been registered as an async handler.
fn OpRegistry::has_async(self : OpRegistry, name : String) -> Bool {
  self.async_handlers.get(name) is Some(_)
}

///|
/// Invokes a previously registered op handler with raw JSON payload.
fn OpRegistry::call(
  self : OpRegistry,
  name : String,
  payload : Json,
) -> Json raise OpDispatchError {
  match self.handlers.get(name) {
    Some(handler) => handler(payload)
    None => raise UnknownOp(name~)
  }
}

///|
fn OpRegistry::handler_name_available(self : OpRegistry, name : String) -> Bool {
  self.handlers.get(name) is None && self.async_handlers.get(name) is None
}

///|
fn validate_op_name(name : String) -> Unit raise OpRegistrationError {
  guard name.trim().to_owned() != "" else { raise EmptyName }
}
