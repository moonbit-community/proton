///|
struct PingPayload {
  name : String?
} derive(ToJson, FromJson)

///|
pub extend PingPayload with ToJson::{to_json}

///|
pub extend PingPayload with FromJson::{from_json}

///|
struct PingReply {
  message : String
  source : String
} derive(ToJson, FromJson)

///|
pub extend PingReply with ToJson::{to_json}

///|
pub extend PingReply with FromJson::{from_json}

///|
struct SlowAddPayload {
  left : Int
  right : Int
  delay_ms : Int?
} derive(ToJson, FromJson)

///|
pub extend SlowAddPayload with ToJson::{to_json}

///|
pub extend SlowAddPayload with FromJson::{from_json}

///|
struct SlowAddReply {
  total : Int
  waited_ms : Int
  source : String
} derive(ToJson, FromJson)

///|
pub extend SlowAddReply with ToJson::{to_json}

///|
pub extend SlowAddReply with FromJson::{from_json}

///|
struct FailPayload {
  message : String?
} derive(ToJson, FromJson)

///|
pub extend FailPayload with ToJson::{to_json}

///|
pub extend FailPayload with FromJson::{from_json}

///|
struct ReportProbePayload {
  report : String
} derive(ToJson, FromJson)

///|
pub extend ReportProbePayload with ToJson::{to_json}

///|
pub extend ReportProbePayload with FromJson::{from_json}

///|
struct ReportProbeReply {
  ok : Bool
} derive(ToJson, FromJson)

///|
pub extend ReportProbeReply with ToJson::{to_json}

///|
pub extend ReportProbeReply with FromJson::{from_json}

///|
suberror AppCommandError {
  Requested(message~ : String)
} derive(Debug)

///|
pub extend AppCommandError with Debug::{to_repr}

///|
let app_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/app-commands",
  js_namespace="appCommands",
)

///|
let ping_command : @proton_contract.Command[PingPayload, PingReply] = app_contract.command(
  "ping",
)

///|
let slow_add_command : @proton_contract.Command[SlowAddPayload, SlowAddReply] = app_contract.command(
  "slowAdd",
)

///|
let fail_command : @proton_contract.Command[FailPayload, String] = app_contract.command(
  "fail",
)

///|
let string_result_command : @proton_contract.Command[PingPayload, String] = app_contract.command(
  "stringResult",
)

///|
let report_probe_command : @proton_contract.Command[
  ReportProbePayload,
  ReportProbeReply,
] = app_contract.command("reportProbe")

///|
fn ping(payload : PingPayload) -> PingReply {
  let name = payload.name.unwrap_or("app")
  PingReply::{
    message: "Hello " + name + " from the app command layer",
    source: "commands",
  }
}

///|
async fn slow_add(payload : SlowAddPayload) -> SlowAddReply {
  let delay_ms = payload.delay_ms.unwrap_or(500)
  @async.sleep(delay_ms)
  SlowAddReply::{
    total: payload.left + payload.right,
    waited_ms: delay_ms,
    source: "commands",
  }
}

///|
fn fail(payload : FailPayload) -> String raise AppCommandError {
  let message = payload.message.unwrap_or("Intentional command failure")
  raise Requested(message~)
}

///|
fn string_result(_payload : PingPayload) -> String {
  "Cancelled"
}

///|
fn report_probe(payload : ReportProbePayload) -> ReportProbeReply {
  println("[app-commands] " + payload.report)
  ReportProbeReply::{ ok: true }
}

///|
fn register_app_commands(registrar : @proton.CommandRegistrar) -> Unit raise {
  registrar.bind(ping_command, (_context, payload) => ping(payload))
  registrar.bind(slow_add_command, (_context, payload) => slow_add(payload))
  registrar.bind(fail_command, (_context, payload) => fail(payload))
  registrar.bind(string_result_command, (_context, payload) => {
    string_result(payload)
  })
  registrar.bind(report_probe_command, (_context, payload) => {
    report_probe(payload)
  })
}

///|
fn app_commands_extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    app_contract,
    [
      ping_command.contract_route(),
      slow_add_command.contract_route(),
      fail_command.contract_route(),
      string_result_command.contract_route(),
      report_probe_command.contract_route(),
    ],
    fn(registrar) raise { register_app_commands(registrar) },
  )
}

///|
/// Run the shared app-command fixture used by the example and E2E suite.
pub async fn run() -> Unit {
  let app = @proton.html(
    "MoonBit App Commands",
    resource,
    width=920,
    height=680,
    debug=true,
  ).capability(@proton_extension.capability(app_commands_extension()))
  app.identifier("dev.proton.app-commands-fixture").run_or_abort()
}
