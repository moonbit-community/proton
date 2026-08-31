///|
let async_extension_add_resource : String =
  #|<!doctype html>
  #|<html><head><meta charset="utf-8"><title>MoonBit Async Add Extension</title></head>
  #|<body><h1>Async Add</h1></body></html>

///|
struct AsyncAddPayload {
  left : Int
  right : Int
} derive(ToJson, FromJson)

///|
pub extend AsyncAddPayload with ToJson::{to_json}

///|
pub extend AsyncAddPayload with FromJson::{from_json}

///|
let async_add_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/async-add",
  js_namespace="add",
)

///|
let async_add_command : @proton_contract.Command[AsyncAddPayload, Int] = async_add_contract.command(
  "slowAdd",
)

///|
fn async_add_extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    async_add_contract,
    [async_add_command.contract_route()],
    fn(registrar) raise {
      registrar.bind(async_add_command, (_context, payload) => {
        @async.sleep(1000)
        payload.left + payload.right
      })
    },
  )
}

///|
pub async fn run_async_extension_add() -> Unit {
  let app = @proton.html(
    "MoonBit Async Add Extension",
    async_extension_add_resource,
    width=840,
    height=560,
    debug=true,
  ).capability(@proton_extension.capability(async_add_extension()))
  app.identifier("dev.proton.e2e-fixtures").run_or_abort()
}

///|
let sync_async_extensions_resource : String =
  #|<!doctype html>
  #|<html><head><meta charset="utf-8"><title>MoonBit Sync + Async Extensions</title></head>
  #|<body><h1>Sync + Async Extensions</h1></body></html>

///|
struct SyncDoublePayload {
  value : Int
} derive(ToJson, FromJson)

///|
pub extend SyncDoublePayload with ToJson::{to_json}

///|
pub extend SyncDoublePayload with FromJson::{from_json}

///|
struct SyncDoubleReply {
  value : Int
  doubled : Int
  source : String
} derive(ToJson, FromJson)

///|
pub extend SyncDoubleReply with ToJson::{to_json}

///|
pub extend SyncDoubleReply with FromJson::{from_json}

///|
struct AsyncSumPayload {
  left : Int
  right : Int
  delay_ms : Int?
} derive(ToJson, FromJson)

///|
pub extend AsyncSumPayload with ToJson::{to_json}

///|
pub extend AsyncSumPayload with FromJson::{from_json}

///|
struct AsyncSumReply {
  total : Int
  waited_ms : Int
  source : String
} derive(ToJson, FromJson)

///|
pub extend AsyncSumReply with ToJson::{to_json}

///|
pub extend AsyncSumReply with FromJson::{from_json}

///|
let sync_math_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/sync-math",
  js_namespace="math",
)

///|
let sync_double_command : @proton_contract.Command[
  SyncDoublePayload,
  SyncDoubleReply,
] = sync_math_contract.command("double")

///|
let async_sum_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/async-add",
  js_namespace="add",
)

///|
let async_sum_command : @proton_contract.Command[AsyncSumPayload, AsyncSumReply] = async_sum_contract.command(
  "slowAdd",
)

///|
fn sync_math_fixture_extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    sync_math_contract,
    [sync_double_command.contract_route()],
    fn(registrar) raise {
      registrar.bind(sync_double_command, (_context, payload) => SyncDoubleReply::{
        value: payload.value,
        doubled: payload.value * 2,
        source: "sync command extension",
      })
    },
  )
}

///|
fn async_add_fixture_extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    async_sum_contract,
    [async_sum_command.contract_route()],
    fn(registrar) raise {
      registrar.bind(async_sum_command, (_context, payload) => {
        let delay_ms = payload.delay_ms.unwrap_or(10)
        @async.sleep(delay_ms)
        AsyncSumReply::{
          total: payload.left + payload.right,
          waited_ms: delay_ms,
          source: "async command extension",
        }
      })
    },
  )
}

///|
pub async fn run_sync_async_extensions() -> Unit {
  let app = @proton.html(
      "MoonBit Sync + Async Extensions",
      sync_async_extensions_resource,
      width=900,
      height=620,
      debug=true,
    )
    .capability(@proton_extension.capability(sync_math_fixture_extension()))
    .capability(@proton_extension.capability(async_add_fixture_extension()))
  app.identifier("dev.proton.e2e-fixtures").run_or_abort()
}

///|
let attribute_codegen_resource : String =
  #|<!doctype html>
  #|<html><head><meta charset="utf-8"><title>Proton Attribute Codegen</title></head>
  #|<body><h1>Attribute Codegen</h1></body></html>

///|
pub async fn run_attribute_codegen_commands() -> Unit {
  let app = @proton.html(
    "Proton Attribute Codegen",
    attribute_codegen_resource,
    width=840,
    height=560,
    debug=true,
  ).capability(@proton_extension.capability(extension()))
  app.identifier("dev.proton.e2e-fixtures").run_or_abort()
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
} derive(ToJson, FromJson)

///|
pub extend EventStartPayload with ToJson::{to_json}

///|
pub extend EventStartPayload with FromJson::{from_json}

///|
struct EventTick {
  run_id : Int
  index : Int
  total : Int
  remaining : Int
} derive(ToJson, FromJson)

///|
pub extend EventTick with ToJson::{to_json}

///|
pub extend EventTick with FromJson::{from_json}

///|
struct EventDone {
  run_id : Int
  total : Int
} derive(ToJson, FromJson)

///|
pub extend EventDone with ToJson::{to_json}

///|
pub extend EventDone with FromJson::{from_json}

///|
struct EventTickerResult {
  ticks : Array[EventTick]
  done : EventDone
} derive(ToJson, FromJson)

///|
pub extend EventTickerResult with ToJson::{to_json}

///|
pub extend EventTickerResult with FromJson::{from_json}

///|
let event_ticker_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/event-ticker",
  js_namespace="ticker",
)

///|
let event_start_command : @proton_contract.Command[
  EventStartPayload,
  EventTickerResult,
] = event_ticker_contract.command("start")

///|
let event_tick_event : @proton_contract.Event[EventTick] = event_ticker_contract.event(
  "tick",
)

///|
let event_done_event : @proton_contract.Event[EventDone] = event_ticker_contract.event(
  "done",
)

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
  @proton_extension.typed(
    event_ticker_contract,
    [event_start_command.contract_route()],
    fn(registrar) raise {
      registrar.bind(event_start_command, run_event_ticker)
    },
  )
}

///|
async fn run_event_ticker(
  context : @proton.CommandContext,
  payload : EventStartPayload,
) -> EventTickerResult {
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
    context.emit(event_tick_event, tick)
  }
  let done = EventDone::{ run_id: payload.run_id, total: count, }
  context.emit(event_done_event, done)
  EventTickerResult::{ ticks, done, }
}

///|
pub async fn run_event_broadcast() -> Unit {
  let app = @proton.html(
    "MoonBit Event Broadcast",
    event_broadcast_resource,
    width=900,
    height=620,
    debug=true,
  ).capability(@proton_extension.capability(event_ticker_extension()))
  app.identifier("dev.proton.e2e-fixtures").run_or_abort()
}

///|
pub async fn run_multi_window() -> Unit {
  match run_multi_window_bridge() {
    Ok(_) => ()
    Err(message) => abort(message)
  }
}

///|
pub async fn run_web_contents_view() -> Unit {
  match run_web_contents_view_app() {
    Ok(_) => ()
    Err(message) => abort(message)
  }
}

///|
pub async fn run_asset_sidecar() -> Unit {
  let entry = @env.get_env_var("PROTON_E2E_ASSET_SIDECAR_ENTRY").unwrap_or(
    "examples/46_asset_sidecar_resources/app/app.html",
  )
  let app = @proton.asset(
    "Asset Sidecar Resources",
    entry,
    width=760,
    height=500,
    debug=true,
  ).capability(@proton_extension.capability(asset_sidecar_extension()))
  app.identifier("dev.proton.e2e-fixtures").run_or_abort()
}

///|
let devtools_resource : String =
  #|<!doctype html>
  #|<html><head><meta charset="utf-8"><title>Proton DevTools API</title></head>
  #|<body><h1>DevTools Bridge Lifecycle</h1></body></html>

///|
pub async fn run_devtools() -> Unit {
  @proton.html(
    "Proton DevTools API",
    devtools_resource,
    width=900,
    height=700,
    debug=true,
  )
  .window_lifecycle(
    on_ready=context => context.handle().browser().open_devtools(),
    on_close=fn(_) { () },
  )
  .identifier("dev.proton.e2e-fixtures")
  .run_or_abort()
}

///|
let i18n_resource : String =
  #|<!doctype html>
  #|<html><head><meta charset="utf-8"><title>Proton I18n E2E</title></head>
  #|<body><h1>Internationalization</h1></body></html>

///|
pub async fn run_i18n() -> Unit {
  let locale = @proton.Locale::parse("zh-CN") catch {
    error => abort(error.message())
  }
  @proton.html(
    "Proton I18n E2E",
    i18n_resource,
    width=720,
    height=480,
    debug=true,
  )
  .locale(locale)
  .identifier("dev.proton.e2e-fixtures")
  .run_or_abort()
}
