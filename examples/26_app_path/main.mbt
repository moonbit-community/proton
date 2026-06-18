///|
async fn main {
  let app = @lepus.html(
    "MoonBit App Runtime + Path",
    960,
    720,
    resource,
    debug=1,
  ).extension(@path.spec())
  app.run_or_abort()
}
