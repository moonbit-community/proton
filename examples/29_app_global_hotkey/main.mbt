///|
async fn main {
  @proton.install_event_loop()
  let app = @proton.html(
    "MoonBit App Runtime + Global Hotkey",
    resource,
    width=960,
    height=740,
    debug=true,
  ).expose(@global_hotkey.extension())
  app.run_or_abort()
}
