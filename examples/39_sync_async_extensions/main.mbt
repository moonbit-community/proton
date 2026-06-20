///|
async fn main {
  let app = @proton.html(
      "MoonBit Sync + Async Extensions",
      resource,
      width=900,
      height=620,
      debug=true,
    )
    .extension(sync_math_extension())
    .extension(async_add_extension())
  app.run_or_abort()
}
