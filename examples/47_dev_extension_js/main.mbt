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
fn ticker_extension() -> @proton_extension.Extension {
  @proton_extension.from_command_spec(
    @proton_command.AppCommandExtensionSpec::new(
      "examples/dev-extension-js",
      "ticker",
      [@proton_command.AppCommandApiDescriptor::new("start")],
      fn(context) {
        context.op_async_result(
          "start",
          async fn(payload : StartPayload) {
            let count = clamp(payload.count, 1, 20)
            let interval_ms = clamp(payload.interval_ms, 25, 2000)
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
          },
          emits_events=true,
        )
        Ok(())
      },
    ),
  )
}

///|
fn main {
  @proton.run(() => @proton.app().extension(ticker_extension()).run_or_abort())
}
