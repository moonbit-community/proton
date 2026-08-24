///|
async fn main {
  let app = @proton.html(
    "MoonBit App Runtime + Path",
    resource,
    width=960,
    height=720,
    debug=true,
  ).capability(@path.capability())
  app.run_or_abort()
}
