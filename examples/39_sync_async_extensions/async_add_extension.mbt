///|
struct SlowAddPayload {
  left : Int
  right : Int
  delay_ms : Int?
} derive(ToJson, FromJson)

///|
struct SlowAddReply {
  total : Int
  waited_ms : Int
  source : String
} derive(ToJson, FromJson)

///|
let async_add_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/async-add",
  js_namespace="add",
)

///|
let slow_add_command : @proton_contract.Command[SlowAddPayload, SlowAddReply] = async_add_contract.command(
  "slowAdd",
)

///|
async fn slow_add(payload : SlowAddPayload) -> SlowAddReply {
  let delay_ms = payload.delay_ms.unwrap_or(800)
  @async.sleep(delay_ms)
  SlowAddReply::{
    total: payload.left + payload.right,
    waited_ms: delay_ms,
    source: "async command extension",
  }
}

///|
fn async_add_extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    async_add_contract,
    [slow_add_command.contract_route()],
    fn(registrar) raise {
      registrar.bind(slow_add_command, (_context, payload) => slow_add(payload))
    },
  )
}
