///|
async fn main {
  let app = @proton.html(
      "MoonBit App Runtime + FS + Path",
      resource,
      width=980,
      height=720,
      debug=true,
    )
    .extension(@fs.extension())
    .extension(@path.extension())
  app.run_or_abort()
}
