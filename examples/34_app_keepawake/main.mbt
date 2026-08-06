///|
async fn main {
  @proton.install_event_loop()
  let app = @proton.html(
    "MoonBit App Runtime + Keep Awake",
    resource,
    width=920,
    height=680,
    debug=true,
  ).expose(@keepawake.extension())
  app.run_or_abort()
}
