///|
async fn main {
  @proton.install_event_loop()
  let app = @proton.html(
    "MoonBit App Runtime + Auto Launch",
    resource,
    width=980,
    height=700,
    debug=true,
  ).expose(@auto_launch.extension())
  app.run_or_abort()
}
