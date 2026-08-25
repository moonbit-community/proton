///|
async fn main {
  let app = @proton.html(
    "MoonBit App Runtime + Path",
    resource,
    width=960,
    height=720,
    debug=true,
  ).capability(@path.capability())
  app.identifier("dev.proton.26-app-path").run_or_abort()
}
