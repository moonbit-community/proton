///|
async fn main {
  let app = @proton.html(
      "MoonBit System Runtime",
      resource,
      width=1080,
      height=760,
      debug=true,
    )
    .expose(@tray.extension())
    .expose(@notification.extension())
    .expose(@global_hotkey.extension())
  app.run_or_abort()
}
