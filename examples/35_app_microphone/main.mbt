///|
async fn main {
  let app = @proton.html(
    "MoonBit App Runtime + Microphone",
    resource,
    width=1040,
    height=760,
    debug=true,
  ).capability(@microphone.capability())
  app.run_or_abort()
}
