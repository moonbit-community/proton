///|
async fn main {
  let app = @proton.html(
    "MoonBit App Runtime + Global Hotkey",
    resource,
    width=960,
    height=740,
    debug=true,
  ).capability(@global_hotkey.capability())
  app.run_or_abort()
}
