///|
priv enum OpHandler {
  Sync((Json) -> Json raise OpDispatchError)
  Async(async (Json) -> Json)
  WithContext(async (AppCommandRequestContext, Json) -> Json)
}

///|
priv struct OpRegistry {
  handlers : Map[String, OpHandler]
}

///|
fn OpRegistry::OpRegistry() -> OpRegistry {
  { handlers: {}, }
}

///|
/// Registers a typed op handler that cannot fail explicitly.
fn[Payload : @json.FromJson, Reply : ToJson] OpRegistry::handle(
  self : OpRegistry,
  name : String,
  callback : (Payload) -> Reply raise,
) -> Unit raise OpRegistrationError {
  validate_op_name(name)
  guard !self.handlers.contains(name) else { raise DuplicateName(name~) }
  self.handlers.set(
    name,
    Sync(fn(payload_json) raise OpDispatchError {
      let payload : Payload = @json.from_json(payload_json) catch {
        err => raise InvalidPayload(name~, detail=err.to_string())
      }
      try callback(payload) catch {
        err => raise HandlerFailed(name~, detail=@debug.render(Repr(err)))
      } noraise {
        reply => ToJson::to_json(reply)
      }
    }),
  )
}

///|
/// Registers a typed async op handler.
fn[Payload : @json.FromJson, Reply : ToJson] OpRegistry::handle_async(
  self : OpRegistry,
  name : String,
  callback : async (Payload) -> Reply,
) -> Unit raise OpRegistrationError {
  validate_op_name(name)
  guard !self.handlers.contains(name) else { raise DuplicateName(name~) }
  self.handlers.set(
    name,
    Async(async fn(payload_json) {
      let payload : Payload = @json.from_json(payload_json) catch {
        err => raise InvalidPayload(name~, detail=err.to_string())
      }
      try callback(payload) catch {
        err => raise HandlerFailed(name~, detail=@debug.render(Repr(err)))
      } noraise {
        reply => ToJson::to_json(reply)
      }
    }),
  )
}

///|
/// Registers a typed async op handler that receives request-scoped context.
fn[Payload : @json.FromJson, Reply : ToJson] OpRegistry::handle_async_with_context(
  self : OpRegistry,
  name : String,
  callback : async (AppCommandRequestContext, Payload) -> Reply,
) -> Unit raise OpRegistrationError {
  validate_op_name(name)
  guard !self.handlers.contains(name) else { raise DuplicateName(name~) }
  self.handlers.set(
    name,
    WithContext(async fn(context, payload_json) {
      let payload : Payload = @json.from_json(payload_json) catch {
        err => raise InvalidPayload(name~, detail=err.to_string())
      }
      try callback(context, payload) catch {
        err => raise HandlerFailed(name~, detail=@debug.render(Repr(err)))
      } noraise {
        reply => ToJson::to_json(reply)
      }
    }),
  )
}

///|
async fn OpRegistry::call(
  self : OpRegistry,
  name : String,
  payload : Json,
  context : AppCommandRequestContext?,
) -> Json {
  match self.handlers.get(name) {
    Some(Sync(handler)) => handler(payload)
    Some(Async(handler)) => handler(payload)
    Some(WithContext(handler)) =>
      match context {
        Some(context) => handler(context, payload)
        None => raise RequestContextRequired(name~)
      }
    None => raise UnknownOp(name~)
  }
}

///|
fn validate_op_name(name : String) -> Unit raise OpRegistrationError {
  guard name.trim().to_owned() != "" else { raise EmptyName }
}
