///|
async fn main {
  @proton.install_event_loop()
  let app = @proton.html(
      "MoonBit Sync + Async Extensions",
      resource,
      width=900,
      height=620,
      debug=true,
    )
    .expose(sync_math_extension())
    .expose(async_add_extension())
  app.run_or_abort()
}
