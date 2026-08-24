///|
async fn main {
  let app = @proton.html(
      "MoonBit System Runtime",
      resource,
      width=1080,
      height=760,
      debug=true,
    )
    .capability(@tray.capability())
    .capability(@notification.capability())
    .capability(@global_hotkey.capability())
  app.run_or_abort()
}
