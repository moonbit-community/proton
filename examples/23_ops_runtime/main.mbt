///|
async fn main {
  let app = @lepus.html(
      "MoonBit Ops Runtime",
      resource,
      width=980,
      height=720,
      debug=true,
    )
    .extension(@fs.extension())
    .extension(@path.extension())
  app.run_or_abort()
}
