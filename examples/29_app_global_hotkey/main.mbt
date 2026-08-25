///|
async fn main {
  let app = @proton.html(
    "MoonBit App Runtime + Global Hotkey",
    resource,
    width=960,
    height=740,
    debug=true,
  ).capability(@global_hotkey.capability())
  app.identifier("dev.proton.29-app-global-hotkey").run_or_abort()
}
