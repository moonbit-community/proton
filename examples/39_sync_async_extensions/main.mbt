///|
async fn main {
  let app = @proton.html(
      "MoonBit Sync + Async Extensions",
      resource,
      width=900,
      height=620,
      debug=true,
    )
    .capability(@proton_extension.capability(sync_math_extension()))
    .capability(@proton_extension.capability(async_add_extension()))
  app.run_or_abort()
}
