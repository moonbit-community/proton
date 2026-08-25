///|
async fn main {
  let app = @proton.html(
    "MoonBit App Runtime + Keep Awake",
    resource,
    width=920,
    height=680,
    debug=true,
  ).capability(@keepawake.capability())
  app.identifier("dev.proton.34-app-keepawake").run_or_abort()
}
