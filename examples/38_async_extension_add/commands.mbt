///|
struct SlowAddRequest {
  left : Int32
  right : Int32
} derive(ToJson, FromJson)

///|
pub extend SlowAddRequest with ToJson::{to_json}

///|
pub extend SlowAddRequest with FromJson::{from_json}

///|
let slow_add_command : @proton_contract.Command[SlowAddRequest, Int32] = generated_extension_contract.command(
  "slowAdd",
)

///|
#proton.command(contract=slow_add_command)
async fn slow_add(request : SlowAddRequest) -> Int32 {
  @async.sleep(1000)
  request.left + request.right
}

///|
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(generated_extension_contract, fn(registrar) raise {
    register_commands(registrar)
  })
}
