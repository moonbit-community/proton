///|
async fn main {
  @proton.install_event_loop()
  let app = @proton.html(
    "MoonBit App Runtime + Path",
    resource,
    width=960,
    height=720,
    debug=true,
  ).expose(@path.extension())
  app.run_or_abort()
}
