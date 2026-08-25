///|
async fn main {
  let app = @proton.asset(
    "Asset Sidecar Resources",
    "46_asset_sidecar_resources/app/app.html",
    width=760,
    height=500,
    debug=true,
  ).capability(@proton_extension.capability(extension()))
  app.identifier("dev.proton.46-asset-sidecar-resources").run_or_abort()
}
