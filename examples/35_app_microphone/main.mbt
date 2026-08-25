///|
async fn main {
  let app = @proton.html(
    "MoonBit App Runtime + Microphone",
    resource,
    width=1040,
    height=760,
    debug=true,
  ).capability(@microphone.capability())
  app.identifier("dev.proton.35-app-microphone").run_or_abort()
}
