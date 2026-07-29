///|
struct AddReply {
  total : Int
  waited_ms : Int
} derive(ToJson, FromJson)

///|
struct AddFinished {
  total : Int
} derive(ToJson, FromJson)

///|
struct AddRequest {
  left : Int
  right : Int
  delay_ms : Int?
} derive(ToJson, FromJson)

///|
let attribute_codegen_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/attribute-codegen",
  js_namespace="add",
)

///|
let attribute_slow_add_command : @proton_contract.Command[AddRequest, AddReply] = attribute_codegen_contract.command(
  "slowAdd",
)

///|
let attribute_add_finished_event : @proton_contract.Event[AddFinished] = attribute_codegen_contract.event(
  "addFinished",
)

///|
#proton.command(contract=attribute_slow_add_command)
async fn slow_add(
  context : @proton.CommandContext,
  request : AddRequest,
) -> AddReply {
  let delay_ms = request.delay_ms.unwrap_or(250)
  @async.sleep(delay_ms)
  let total = request.left + request.right
  context.emit(attribute_add_finished_event, AddFinished::{ total, })
  AddReply::{ total, waited_ms: delay_ms }
}

///|
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    attribute_codegen_contract,
    generated_extension_command_routes(),
    fn(registrar) raise { register_commands(registrar) },
  )
}
