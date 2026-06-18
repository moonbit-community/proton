///|
struct StartPayload {
  run_id : Int
  count : Int
  interval_ms : Int
} derive(FromJson)

///|
struct TickEvent {
  run_id : Int
  index : Int
  total : Int
  remaining : Int
} derive(ToJson)

///|
struct DoneEvent {
  run_id : Int
  total : Int
} derive(ToJson)

///|
struct TickerResult {
  ticks : Array[TickEvent]
  done : DoneEvent
} derive(ToJson)

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
fn ticker_extension() -> @app.AppCommandExtensionSpec {
  @app.AppCommandExtensionSpec::new(
    "examples/event-ticker",
    "ticker",
    [@app.AppCommandApiDescriptor::new("start")],
    fn(context) {
      context.op_async_result("start", async fn(payload : StartPayload) {
        let count = clamp(payload.count, 1, 20)
        let interval_ms = clamp(payload.interval_ms, 100, 2000)
        let ticks : Array[TickEvent] = []
        for index in 1..<=count {
          @async.sleep(interval_ms)
          let tick = TickEvent::{
            run_id: payload.run_id,
            index,
            total: count,
            remaining: count - index,
          }
          ticks.push(tick)
          context.emit("tick", tick)
        }
        let done = DoneEvent::{ run_id: payload.run_id, total: count }
        context.emit("done", done)
        Ok(TickerResult::{ ticks, done })
      })
      Ok(())
    },
  )
}

///|
async fn main {
  let app = @app.html("MoonBit Event Broadcast", 900, 620, resource, debug=1).command(
    ticker_extension(),
  )
  app.run_or_abort()
}
