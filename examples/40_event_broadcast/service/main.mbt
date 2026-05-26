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
async fn main {
  let host = @core.AppServiceHost::new()
  host.op_async_result("ext:ticker/start", async fn(payload : StartPayload) {
    let count = clamp(payload.count, 1, 20)
    let interval_ms = clamp(payload.interval_ms, 100, 2000)
    let ticks : Array[TickEvent] = []
    for index in 1..<=count {
      @async.sleep(interval_ms)
      ticks.push(TickEvent::{
        run_id: payload.run_id,
        index,
        total: count,
        remaining: count - index,
      })
    }
    Ok(TickerResult::{
      ticks,
      done: DoneEvent::{ run_id: payload.run_id, total: count },
    })
  })
  host.run()
  host.close()
}
