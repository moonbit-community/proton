///|
struct AddReply {
  total : Int
  waited_ms : Int
} derive(ToJson, FromJson)

///|
pub extend AddReply with ToJson::{to_json}

///|
pub extend AddReply with FromJson::{from_json}

///|
struct AddRequest {
  left : Int
  right : Int
  delay_ms : Int?
} derive(ToJson, FromJson)

///|
pub extend AddRequest with ToJson::{to_json}

///|
pub extend AddRequest with FromJson::{from_json}

///|
struct AddFinished {
  total : Int
} derive(ToJson, FromJson)

///|
pub extend AddFinished with ToJson::{to_json}

///|
pub extend AddFinished with FromJson::{from_json}

///|
let slow_add_command : @proton_contract.Command[AddRequest, AddReply] = generated_extension_contract.command(
  "slowAdd",
)

///|
let add_finished_event : @proton_contract.Event[AddFinished] = generated_extension_contract.event(
  "addFinished",
)

///|
#proton.command(contract=slow_add_command)
async fn slow_add(
  context : @proton.CommandContext,
  request : AddRequest,
) -> AddReply {
  let delay_ms = request.delay_ms.unwrap_or(250)
  @async.sleep(delay_ms)
  let total = request.left + request.right
  context.emit(add_finished_event, AddFinished::{ total, })
  AddReply::{ total, waited_ms: delay_ms }
}

///|
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    generated_extension_contract,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
  )
}
