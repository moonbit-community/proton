///|
async fn main {
  let app = @lepus.html(
    "MoonBit App Runtime + Global Hotkey",
    resource,
    width=960,
    height=740,
    debug=true,
  ).extension(@global_hotkey.extension())
  app.run_or_abort()
}
