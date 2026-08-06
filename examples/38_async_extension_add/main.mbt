///|
async fn main {
  @proton.install_event_loop()
  let app = @proton.html(
    "MoonBit Async Add Extension",
    resource,
    width=840,
    height=560,
    debug=true,
  ).expose(extension())
  app.run_or_abort()
}
