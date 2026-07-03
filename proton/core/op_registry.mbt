///|
priv struct OpRegistry {
  handlers : Map[String, (Json) -> Result[Json, String]]
  async_handlers : Map[
    String,
    async (AppCommandRequestContext, Json) -> Result[Json, String],
  ]
}

///|
/// Creates an empty op handler registry.
fn OpRegistry::new() -> OpRegistry {
  OpRegistry::{ handlers: {}, async_handlers: {} }
}

///|
/// Registers a typed op handler that cannot fail explicitly.
fn[Payload : @json.FromJson, Reply : ToJson] OpRegistry::handle(
  self : OpRegistry,
  name : String,
  callback : (Payload) -> Reply,
) -> Unit {
  self.handle_result(name, fn(payload) { Ok(callback(payload)) })
}

///|
/// Registers a typed op handler that can return a string error.
fn[Payload : @json.FromJson, Reply : ToJson] OpRegistry::handle_result(
  self : OpRegistry,
  name : String,
  callback : (Payload) -> Result[Reply, String],
) -> Unit {
  guard validate_op_name(name) is Ok(_) else {
    abort("OpRegistry::handle_result: op name must not be empty")
  }
  guard self.handler_name_available(name) else {
    abort("OpRegistry::handle_result: op already registered: " + name)
  }
  self.handlers.set(name, fn(payload_json) {
    try {
      let payload : Payload = @json.from_json(payload_json)
      callback(payload).map(fn(reply) { ToJson::to_json(reply) })
    } catch {
      err => Err(err.to_string())
    }
  })
}

///|
/// Registers a typed async op handler that cannot fail explicitly.
fn[Payload : @json.FromJson, Reply : ToJson] OpRegistry::handle_async(
  self : OpRegistry,
  name : String,
  callback : async (Payload) -> Reply,
) -> Unit {
  self.handle_async_result(name, async fn(payload) { Ok(callback(payload)) })
}

///|
/// Registers a typed async op handler that can return a string error.
fn[Payload : @json.FromJson, Reply : ToJson] OpRegistry::handle_async_result(
  self : OpRegistry,
  name : String,
  callback : async (Payload) -> Result[Reply, String],
) -> Unit {
  guard validate_op_name(name) is Ok(_) else {
    abort("OpRegistry::handle_async_result: op name must not be empty")
  }
  guard self.handler_name_available(name) else {
    abort("OpRegistry::handle_async_result: op already registered: " + name)
  }
  self.async_handlers.set(name, async fn(_context, payload_json) {
    let result = try {
      let payload : Payload = @json.from_json(payload_json)
      callback(payload).map(fn(reply) { ToJson::to_json(reply) })
    } catch {
      err => Err(err.to_string())
    }
    result
  })
}

///|
/// Registers a typed async op handler that receives request-scoped context and can fail.
fn[Payload : @json.FromJson, Reply : ToJson] OpRegistry::handle_async_result_with_context(
  self : OpRegistry,
  name : String,
  callback : async (AppCommandRequestContext, Payload) -> Result[Reply, String],
) -> Unit {
  guard validate_op_name(name) is Ok(_) else {
    abort(
      "OpRegistry::handle_async_result_with_context: op name must not be empty",
    )
  }
  guard self.handler_name_available(name) else {
    abort(
      "OpRegistry::handle_async_result_with_context: op already registered: " +
      name,
    )
  }
  self.async_handlers.set(name, async fn(context, payload_json) {
    let result = try {
      let payload : Payload = @json.from_json(payload_json)
      callback(context, payload).map(fn(reply) { ToJson::to_json(reply) })
    } catch {
      err => Err(err.to_string())
    }
    result
  })
}

///|
/// Runs a previously registered async op handler on the current async loop.
async fn OpRegistry::call_async_direct(
  self : OpRegistry,
  name : String,
  payload : Json,
) -> Result[Json, String] {
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
) -> Result[Json, String] {
  match self.async_handlers.get(name) {
    Some(handler) =>
      handler(context, payload) catch {
        err => Err(err.to_string())
      }
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
) -> Result[Json, String] {
  match self.handlers.get(name) {
    Some(handler) => handler(payload)
    None => Err("Unknown op: " + name)
  }
}

///|
fn OpRegistry::handler_name_available(self : OpRegistry, name : String) -> Bool {
  self.handlers.get(name) is None && self.async_handlers.get(name) is None
}

///|
fn validate_op_name(name : String) -> Result[Unit, String] {
  guard name.trim().to_owned() != "" else {
    return Err("op name must not be empty")
  }
  Ok(())
}
