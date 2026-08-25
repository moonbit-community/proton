///|
async fn main {
  let app = @proton.html(
    "MoonBit App Runtime + Notification",
    resource,
    width=940,
    height=720,
    debug=true,
  ).capability(@notification.capability())
  app.identifier("dev.proton.27-app-notification").run_or_abort()
}
