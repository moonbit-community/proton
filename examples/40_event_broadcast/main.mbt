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
fn register_ticker_commands(host : @core.AppCommandHost) -> Unit {
  host.op_async_result("ext:ticker/start", async fn(payload : StartPayload) {
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
      host.emit_extension("ticker", "tick", tick)
    }
    let done = DoneEvent::{ run_id: payload.run_id, total: count }
    host.emit_extension("ticker", "done", done)
    Ok(TickerResult::{ ticks, done })
  })
}

///|
fn main {
  if @app.is_framework_process() {
    match @app.run_framework_process_from_cli() {
      Ok(_) => ()
      Err(error) => abort(error)
    }
    return
  }
  let framework_command = match @app.current_executable_command() {
    Ok(command) => command
    Err(error) => abort(error)
  }
  let ticker_extension = @app.AppCommandExtensionDescriptor::new(
    "examples/event-ticker",
    "ticker",
    [@app.AppCommandApiDescriptor::new("start")],
  )
  let commands = @app.AppCommandsConfig::new(["ext:ticker/start"], extensions=[
    ticker_extension,
  ])
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new(
      "MoonBit Event Broadcast",
      900,
      620,
      size_hint=@manifest.WindowSizeHint::None,
    ),
    @manifest.AppEntry::Html(resource),
    debug=1,
  )
  let host = @core.AppCommandHost::new()
  register_ticker_commands(host)
  match
    @app.run_app_command_host_with_framework_process(
      manifest,
      framework_command,
      host,
      commands,
      framework_args=[@app.framework_process_arg()],
    ) {
    Ok(_) => ()
    Err(error) => abort(error)
  }
}
