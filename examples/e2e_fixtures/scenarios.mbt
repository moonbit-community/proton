///|
let async_extension_add_resource : String =
  #|<!doctype html>
  #|<html><head><meta charset="utf-8"><title>MoonBit Async Add Extension</title></head>
  #|<body><h1>Async Add</h1></body></html>

///|
struct AsyncAddPayload {
  left : Int
  right : Int
} derive(FromJson)

///|
fn async_add_extension() -> @proton_extension.Extension {
  @proton_extension.from_command_spec(
    @proton_command.AppCommandExtensionSpec::new(
      "examples/async-add",
      "add",
      [@proton_command.AppCommandApiDescriptor::new("slowAdd")],
      fn(context) raise {
        context.op_async("slowAdd", async fn(payload : AsyncAddPayload) {
          @async.sleep(1000)
          payload.left + payload.right
        })
      },
    ),
  )
}

///|
pub fn run_async_extension_add() -> Unit {
  @proton.run(() => {
    let app = @proton.html(
      "MoonBit Async Add Extension",
      async_extension_add_resource,
      width=840,
      height=560,
      debug=true,
    ).extension(async_add_extension())
    app.run_or_abort()
  })
}

///|
let sync_async_extensions_resource : String =
  #|<!doctype html>
  #|<html><head><meta charset="utf-8"><title>MoonBit Sync + Async Extensions</title></head>
  #|<body><h1>Sync + Async Extensions</h1></body></html>

///|
struct SyncDoublePayload {
  value : Int
} derive(FromJson)

///|
struct SyncDoubleReply {
  value : Int
  doubled : Int
  source : String
} derive(ToJson)

///|
struct AsyncSumPayload {
  left : Int
  right : Int
  delay_ms : Int?
} derive(FromJson)

///|
struct AsyncSumReply {
  total : Int
  waited_ms : Int
  source : String
} derive(ToJson)

///|
fn sync_math_fixture_extension() -> @proton_extension.Extension {
  @proton_extension.from_command_spec(
    @proton_command.AppCommandExtensionSpec::new(
      "examples/sync-math",
      "math",
      [@proton_command.AppCommandApiDescriptor::new("double")],
      fn(context) raise {
        context.op("double", fn(payload : SyncDoublePayload) {
          SyncDoubleReply::{
            value: payload.value,
            doubled: payload.value * 2,
            source: "sync command extension",
          }
        })
      },
    ),
  )
}

///|
fn async_add_fixture_extension() -> @proton_extension.Extension {
  @proton_extension.from_command_spec(
    @proton_command.AppCommandExtensionSpec::new(
      "examples/async-add",
      "add",
      [@proton_command.AppCommandApiDescriptor::new("slowAdd")],
      fn(context) raise {
        context.op_async("slowAdd", async fn(payload : AsyncSumPayload) {
          let delay_ms = payload.delay_ms.unwrap_or(10)
          @async.sleep(delay_ms)
          AsyncSumReply::{
            total: payload.left + payload.right,
            waited_ms: delay_ms,
            source: "async command extension",
          }
        })
      },
    ),
  )
}

///|
pub fn run_sync_async_extensions() -> Unit {
  @proton.run(() => {
    let app = @proton.html(
        "MoonBit Sync + Async Extensions",
        sync_async_extensions_resource,
        width=900,
        height=620,
        debug=true,
      )
      .extension(sync_math_fixture_extension())
      .extension(async_add_fixture_extension())
    app.run_or_abort()
  })
}

///|
let attribute_codegen_resource : String =
  #|<!doctype html>
  #|<html><head><meta charset="utf-8"><title>Proton Attribute Codegen</title></head>
  #|<body><h1>Attribute Codegen</h1></body></html>

///|
pub fn run_attribute_codegen_commands() -> Unit {
  @proton.run(() => {
    let app = @proton.html(
      "Proton Attribute Codegen",
      attribute_codegen_resource,
      width=840,
      height=560,
      debug=true,
    ).extension(extension())
    app.run_or_abort()
  })
}

///|
let event_broadcast_resource : String =
  #|<!doctype html>
  #|<html><head><meta charset="utf-8"><title>MoonBit Event Broadcast</title></head>
  #|<body><h1>Event Broadcast</h1></body></html>

///|
struct EventStartPayload {
  run_id : Int
  count : Int
  interval_ms : Int
} derive(FromJson)

///|
struct EventTick {
  run_id : Int
  index : Int
  total : Int
  remaining : Int
} derive(ToJson)

///|
struct EventDone {
  run_id : Int
  total : Int
} derive(ToJson)

///|
struct EventTickerResult {
  ticks : Array[EventTick]
  done : EventDone
} derive(ToJson)

///|
fn clamp_event_value(value : Int, min : Int, max : Int) -> Int {
  if value < min {
    min
  } else if value > max {
    max
  } else {
    value
  }
}

///|
fn event_ticker_extension() -> @proton_extension.Extension {
  @proton_extension.from_command_spec(
    @proton_command.AppCommandExtensionSpec::new(
      "examples/event-ticker",
      "ticker",
      [@proton_command.AppCommandApiDescriptor::new("start")],
      fn(context) raise {
        context.op_async(
          "start",
          async fn(payload : EventStartPayload) {
            let count = clamp_event_value(payload.count, 1, 20)
            let interval_ms = clamp_event_value(payload.interval_ms, 100, 2000)
            let ticks : Array[EventTick] = []
            for index in 1..<=count {
              @async.sleep(interval_ms)
              let tick = EventTick::{
                run_id: payload.run_id,
                index,
                total: count,
                remaining: count - index,
              }
              ticks.push(tick)
              context.emit("tick", tick)
            }
            let done = EventDone::{ run_id: payload.run_id, total: count }
            context.emit("done", done)
            EventTickerResult::{ ticks, done }
          },
          emits_events=true,
        )
      },
    ),
  )
}

///|
pub fn run_event_broadcast() -> Unit {
  @proton.run(() => {
    let app = @proton.html(
      "MoonBit Event Broadcast",
      event_broadcast_resource,
      width=900,
      height=620,
      debug=true,
    ).extension(event_ticker_extension())
    app.run_or_abort()
  })
}

///|
pub fn run_multi_window() -> Unit {
  @proton.run(() => {
    match run_multi_window_bridge() {
      Ok(_) => ()
      Err(message) => abort(message)
    }
  })
}

///|
pub fn run_asset_sidecar() -> Unit {
  @proton.run(() => {
    let app = @proton.asset(
      "Asset Sidecar Resources",
      "examples/46_asset_sidecar_resources/app/app.html",
      width=760,
      height=500,
      debug=true,
    ).extension(asset_sidecar_extension())
    app.run_or_abort()
  })
}
