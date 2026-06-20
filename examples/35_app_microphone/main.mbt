///|
async fn main {
  let app = @lepus.html(
    "MoonBit App Runtime + Microphone",
    resource,
    width=1040,
    height=760,
    debug=true,
  ).extension(@microphone.extension())
  app.run_or_abort()
}
