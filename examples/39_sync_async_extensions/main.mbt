///|
async fn main {
  let app = @lepus.html(
      "MoonBit Sync + Async Extensions",
      900,
      620,
      resource,
      debug=1,
    )
    .command(sync_math_extension())
    .command(async_add_extension())
  app.run_or_abort()
}
