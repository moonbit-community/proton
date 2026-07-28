///|
struct DoublePayload {
  value : Int
} derive(ToJson, FromJson)

///|
struct DoubleReply {
  value : Int
  doubled : Int
  source : String
} derive(ToJson, FromJson)

///|
let sync_math_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/sync-math",
  js_namespace="math",
)

///|
let double_command : @proton_contract.Command[DoublePayload, DoubleReply] = sync_math_contract.command(
  "double",
)

///|
fn double(payload : DoublePayload) -> DoubleReply {
  DoubleReply::{
    value: payload.value,
    doubled: payload.value * 2,
    source: "sync command extension",
  }
}

///|
fn sync_math_extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    sync_math_contract,
    [double_command.contract_route()],
    fn(registrar) raise {
      registrar.bind(double_command, (_context, payload) => double(payload))
    },
  )
}
