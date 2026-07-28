///|
struct SlowAddRequest {
  left : Int
  right : Int
} derive(ToJson, FromJson)

///|
let slow_add_command : @proton_contract.Command[SlowAddRequest, Int] = generated_extension_contract.command(
  "slowAdd",
)

///|
#proton.command(contract=slow_add_command)
async fn slow_add(request : SlowAddRequest) -> Int {
  @async.sleep(1000)
  request.left + request.right
}

///|
fn extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    generated_extension_contract,
    generated_extension_command_routes(),
    fn(_context, registrar) raise { register_commands(registrar) },
  )
}
