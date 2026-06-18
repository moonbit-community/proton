///|
async fn main {
  let app = @lepus.html("MoonBit System Runtime", 1080, 760, resource, debug=1)
    .command(@tray.generated_app_command_extension())
    .command(@notification.generated_app_command_extension())
    .command(@global_hotkey.generated_app_command_extension())
  app.run_or_abort()
}
