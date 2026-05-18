///|
let extension_id = "examples/event-ticker"

///|
let extension_namespace = "ticker"

///|
struct StartPayload {
  run_id : Int
  count : Int
  interval_ms : Int
} derive(ToJson, FromJson, Eq, Debug)

///|
struct EmptyReply {} derive(ToJson, FromJson, Eq, Debug)

///|
struct TickEvent {
  run_id : Int
  index : Int
  total : Int
  remaining : Int
} derive(ToJson, FromJson, Eq, Debug)

///|
struct DoneEvent {
  run_id : Int
  total : Int
} derive(ToJson, FromJson, Eq, Debug)

///|
fn clamp(value : Int, min : Int, max : Int) -> Int {
  if value < min {
    min
  } else if value > max {
    max
  } else {
    value
  }
}

///|
pub fn extension() -> @core.Extension {
  @core.Extension::new(extension_id, extension_namespace, fn(extension) {
    extension.op_async_result("start", async fn(payload : StartPayload) {
      let count = clamp(payload.count, 1, 20)
      let interval_ms = clamp(payload.interval_ms, 100, 2000)
      for index in 1..<=count {
        @async.sleep(interval_ms)
        extension.emit("tick", TickEvent::{
          run_id: payload.run_id,
          index,
          total: count,
          remaining: count - index,
        })
      }
      extension.emit("done", DoneEvent::{ run_id: payload.run_id, total: count })
      Ok(EmptyReply::{  })
    })
  })
}
