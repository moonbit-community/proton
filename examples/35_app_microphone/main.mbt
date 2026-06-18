///|
async fn main {
  let app = @lepus.html(
    "MoonBit App Runtime + Microphone",
    1040,
    760,
    resource,
    debug=1,
  ).command(@microphone.generated_app_command_extension())
  app.run_or_abort()
}
