///|
async fn main {
  let app = @lepus.html(
      "MoonBit App Runtime + FS + Path",
      980,
      720,
      resource,
      debug=1,
    )
    .extension(@fs.spec())
    .extension(@path.spec())
  app.run_or_abort()
}
