///|
struct AddRequest {
  left : Int
  right : Int
} derive(ToJson, FromJson)

///|
struct ReportProbeRequest {
  report : String
} derive(ToJson, FromJson)

///|
let add_command : @proton_contract.Command[AddRequest, Int] = generated_extension_contract.command(
  "add",
)

///|
let add_later_command : @proton_contract.Command[AddRequest, Int] = generated_extension_contract.command(
  "addLater",
)

///|
let report_probe_command : @proton_contract.Command[ReportProbeRequest, Unit] = generated_extension_contract.command(
  "reportProbe",
)

///|
#proton.command(contract=add_command)
fn add(request : AddRequest) -> Int {
  request.left + request.right
}

///|
#proton.command(contract=add_later_command)
async fn add_later(request : AddRequest) -> Int {
  @async.sleep(800)
  request.left + request.right
}

///|
#proton.command(contract=report_probe_command)
fn report_probe(request : ReportProbeRequest) -> Unit {
  println("[asset-sidecar] " + request.report)
  @mbfs.create_dir("target") catch {
    _ => ()
  }
  @mbfs.write_string_to_file("target/asset-sidecar.probe.json", request.report) catch {
    _ => ()
  }
}

///|
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    generated_extension_contract,
    generated_extension_command_routes(),
    fn(_context, registrar) raise { register_commands(registrar) },
  )
}
