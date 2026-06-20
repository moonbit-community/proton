///|
async fn main {
  let app = @proton.html(
    "MoonBit App Runtime + Path",
    resource,
    width=960,
    height=720,
    debug=true,
  ).extension(@path.extension())
  app.run_or_abort()
}
