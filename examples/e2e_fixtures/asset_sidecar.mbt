///|
struct AssetSidecarAddPayload {
  left : Int
  right : Int
} derive(ToJson, FromJson)

///|
struct AssetSidecarReportPayload {
  report : String
} derive(ToJson, FromJson)

///|
let asset_sidecar_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id="examples/asset-sidecar-e2e",
  js_namespace="add",
)

///|
let asset_sidecar_add_command : @proton_contract.Command[
  AssetSidecarAddPayload,
  Int,
] = asset_sidecar_contract.command("add")

///|
let asset_sidecar_add_later_command : @proton_contract.Command[
  AssetSidecarAddPayload,
  Int,
] = asset_sidecar_contract.command("addLater")

///|
let asset_sidecar_report_command : @proton_contract.Command[
  AssetSidecarReportPayload,
  Unit,
] = asset_sidecar_contract.command("reportProbe")

///|
fn asset_sidecar_extension() -> @proton_extension.Extension {
  @proton_extension.typed(
    asset_sidecar_contract,
    [
      asset_sidecar_add_command.contract_route(),
      asset_sidecar_add_later_command.contract_route(),
      asset_sidecar_report_command.contract_route(),
    ],
    fn(registrar) raise {
      registrar.bind(asset_sidecar_add_command, (_context, payload) => {
        payload.left + payload.right
      })
      registrar.bind(asset_sidecar_add_later_command, (_context, payload) => {
        @async.sleep(800)
        payload.left + payload.right
      })
      registrar.bind(asset_sidecar_report_command, (_context, payload) => {
        println("[asset-sidecar-e2e] " + payload.report)
      })
    },
  )
}
