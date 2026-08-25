///|
async fn main {
  let app = @proton.html(
    "MoonBit App Runtime + Tray",
    resource,
    width=940,
    height=720,
    debug=true,
  ).capability(@tray.capability())
  app.identifier("dev.proton.28-app-tray").run_or_abort()
}
