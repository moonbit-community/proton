///|
async fn main {
  let app = @lepus.html(
    "MoonBit App Runtime + Tray",
    resource,
    width=940,
    height=720,
    debug=true,
  ).extension(@tray.extension())
  app.run_or_abort()
}
