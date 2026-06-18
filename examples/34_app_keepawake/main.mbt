///|
async fn main {
  let app = @lepus.html(
    "MoonBit App Runtime + Keep Awake",
    920,
    680,
    resource,
    debug=1,
  ).command(@keepawake.generated_app_command_extension())
  app.run_or_abort()
}
