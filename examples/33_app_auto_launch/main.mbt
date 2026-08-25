///|
async fn main {
  let app = @proton.html(
    "MoonBit App Runtime + Auto Launch",
    resource,
    width=980,
    height=700,
    debug=true,
  ).capability(@auto_launch.capability())
  app.identifier("dev.proton.33-app-auto-launch").run_or_abort()
}
