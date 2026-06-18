///|
async fn main {
  let app = @lepus.html(
    "MoonBit App Runtime + Global Hotkey",
    960,
    740,
    resource,
    debug=1,
  ).command(@global_hotkey.generated_app_command_extension())
  app.run_or_abort()
}
