///|
struct StartPayload {
  run_id : Int
  count : Int
  interval_ms : Int
} derive(ToJson, FromJson)

///|
pub extend StartPayload with ToJson::{to_json}

///|
pub extend StartPayload with FromJson::{from_json}

///|
struct TickEvent {
  run_id : Int
  index : Int
  total : Int
  remaining : Int
} derive(ToJson, FromJson)

///|
pub extend TickEvent with ToJson::{to_json}

///|
pub extend TickEvent with FromJson::{from_json}

///|
struct DoneEvent {
  run_id : Int
  total : Int
} derive(ToJson, FromJson)

///|
pub extend DoneEvent with ToJson::{to_json}

///|
pub extend DoneEvent with FromJson::{from_json}

///|
struct TickerResult {
  ticks : Array[TickEvent]
  done : DoneEvent
} derive(ToJson, FromJson)

///|
pub extend TickerResult with ToJson::{to_json}

///|
pub extend TickerResult with FromJson::{from_json}

///|
let ticker_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/event-ticker",
  js_namespace="ticker",
)

///|
let start_command : @proton_contract.Command[StartPayload, TickerResult] = ticker_contract.command(
  "start",
)

///|
let tick_event : @proton_contract.Event[TickEvent] = ticker_contract.event(
  "tick",
)

///|
let done_event : @proton_contract.Event[DoneEvent] = ticker_contract.event(
  "done",
)

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
  @proton_extension.typed(ticker_contract, [start_command.contract_route()], fn(
    registrar,
  ) raise {
    registrar.bind(start_command, run_ticker)
  })
}

///|
async fn run_ticker(
  context : @proton.CommandContext,
  payload : StartPayload,
) -> TickerResult {
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
    context.emit(tick_event, tick)
  }
  let done = DoneEvent::{ run_id: payload.run_id, total: count }
  context.emit(done_event, done)
  TickerResult::{ ticks, done }
}

///|
async fn main {
  let app = @proton.html(
    "MoonBit Event Broadcast",
    resource,
    width=900,
    height=620,
    debug=true,
  ).capability(@proton_extension.capability(ticker_extension()))
  app.run_or_abort()
}
