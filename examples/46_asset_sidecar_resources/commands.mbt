///|
struct AddRequest {
  left : Int32
  right : Int32
} derive(ToJson, FromJson)

///|
pub extend AddRequest with ToJson::{to_json}

///|
pub extend AddRequest with FromJson::{from_json}

///|
struct ReportProbeRequest {
  report : String
} derive(ToJson, FromJson)

///|
pub extend ReportProbeRequest with ToJson::{to_json}

///|
pub extend ReportProbeRequest with FromJson::{from_json}

///|
let add_command : @proton_contract.Command[AddRequest, Int32] = generated_extension_contract.command(
  "add",
)

///|
let add_later_command : @proton_contract.Command[AddRequest, Int32] = generated_extension_contract.command(
  "addLater",
)

///|
let report_probe_command : @proton_contract.Command[ReportProbeRequest, Unit] = generated_extension_contract.command(
  "reportProbe",
)

///|
#proton.command(contract=add_command)
fn add(request : AddRequest) -> Int32 {
  request.left + request.right
}

///|
#proton.command(contract=add_later_command)
async fn add_later(request : AddRequest) -> Int32 {
  @async.sleep(800)
  request.left + request.right
}

///|
#proton.command(contract=report_probe_command)
fn report_probe(request : ReportProbeRequest) -> Unit {
  println("[asset-sidecar] " + request.report)
}

///|
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(generated_extension_contract, fn(registrar) raise {
    register_commands(registrar)
  })
}
