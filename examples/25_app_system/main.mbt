///|
async fn main {
  let app = @lepus.html(
      "MoonBit System Runtime",
      resource,
      width=1080,
      height=760,
      debug=true,
    )
    .extension(@tray.extension())
    .extension(@notification.extension())
    .extension(@global_hotkey.extension())
  app.run_or_abort()
}
